#Requires -Version 5.1
<#
.SYNOPSIS
  bonjour-systeme.ps1 — Brief système animé, façon "docker deploy".
.DESCRIPTION
  Affiche un brief stylé dans le terminal :
    - l'utilisateur, la date et l'heure
    - la version de Windows
    - les 12 applications les plus lancées depuis un mois
      (via le compteur UserAssist de l'Explorateur ; sinon FeatureUsage)
    - le point santé : RAM, disque, CPU, batterie
    - bonus : IP locale et uptime de la machine
  Effets : bannière dégradée, typewriter, spinner, jauges animées.
.ENCODAGE
  Le source est volontairement 100% ASCII : tous les symboles Unicode
  (jauges, spinner, coches) sont construits au runtime via [char]0xXXXX,
  et les accents français sont auto-réparés par la fonction Fix().
  Si le fichier est détecté UTF-8 sans BOM, le script se réécrit
  automatiquement avec BOM pour que les lancements suivants soient natifs.
.USAGE
  powershell -ExecutionPolicy Bypass -File .\bonjour-systeme.ps1
  Ajoute -Fast pour désactiver les animations (mode instantané).
#>
param([switch]$Fast)

$ErrorActionPreference = 'SilentlyContinue'
$script:CI = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')

# ─────────────────────────────────────────────────────────────────────────────
# 0. Console : UTF-8 + séquences ANSI (couleurs 24 bits)
# ─────────────────────────────────────────────────────────────────────────────
# NB : on ne touche PAS a [Console]::OutputEncoding par defaut ! En console
# classique (powershell.exe, fond bleu), forcer l'UTF-8 fait encoder accents
# et symboles en UTF-8 alors que la console les lit en CP850 -> mojibake.
# PowerShell ecrit nativement en Unicode (WriteConsoleW) : tout s'affiche bien
# sans rien toucher. On passe en UTF-8 uniquement si la sortie est redirigee.
try {
    if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
} catch { }
$script:ESC = [string][char]27
$script:VT  = $false
try {
    if (-not ('Native.Console' -as [type])) {
        Add-Type -Namespace Native -Name Console -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out int lpMode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int dwMode);
'@
    }
    $h = [Native.Console]::GetStdHandle(-11)
    $m = 0
    $null = [Native.Console]::GetConsoleMode($h, [ref]$m)
    $script:VT = [Native.Console]::SetConsoleMode($h, ($m -bor 4))  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
} catch { $script:VT = $false }

# ── Auto-réparation d'encodage ───────────────────────────────────────────────
# Windows PowerShell 5.1 lit un .ps1 sans BOM en ANSI (CP1252) : les accents
# et symboles UTF-8 se retrouvent en "mojibake" (Ã©, â, etc.).
# Detection : le literal ci-dessous vaut 1 caractere si le fichier est bien
# decode, 2 si il a ete lu en ANSI.
$script:Moji = (('é').Length -ne 1)

# Si le fichier sur disque est de l'UTF-8 valide, on le re-sauvegarde avec
# BOM : les prochains lancements seront nativement corrects.
$script:Repaired = $false
if ($script:Moji -and $PSCommandPath) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $strict.GetString($bytes)   # echoue si ce n'est pas de l'UTF-8
        if (-not $text.StartsWith([string][char]0xFEFF)) {
            [System.IO.File]::WriteAllText($PSCommandPath, $text, (New-Object System.Text.UTF8Encoding($true)))
            $script:Repaired = $true
        }
    } catch { }
}

# Répare a la volee une chaine "mojibakee" (UTF-8 lu comme CP1252).
# Ne touche pas les chaines legitimes grace au test de motif UTF-8/CP1252.
function Fix {
    param([string]$s)
    if (-not $script:Moji -or -not $s) { return $s }
    if ($s -cmatch '[\u00C2-\u00F4][\u0080-\u00BF]') {
        try {
            $enc1252 = [System.Text.Encoding]::GetEncoding(1252)
            return [System.Text.Encoding]::UTF8.GetString($enc1252.GetBytes($s))
        } catch { return $s }
    }
    return $s
}

# Symboles Unicode construits au runtime (source 100% ASCII)
$Ch = @{
    Block  = [string][char]0x2588   # jauge pleine
    Empty  = [string][char]0x2591   # jauge vide
    Line   = [string][char]0x2500   # trait de section
    Check  = [string][char]0x2713   # coche
    Star   = [string][char]0x2726   # etoile
    Gem    = [string][char]0x25C6   # losange de section
    Corner = [string][char]0x2514   # coin de note
    Dot    = [string][char]0xB7     # point median
    Dash   = [string][char]0x2014   # tiret long
    DLine  = [string][char]0x2550   # trait double (bandeau de banniere)
}
$Ch.Spinner = @((0x280B,0x2819,0x2839,0x2838,0x283C,0x2834,0x2826,0x2827,0x2807,0x280F) | ForEach-Object { [string][char]$_ })

try { $Host.UI.RawUI.WindowTitle = 'Bonjour, ' + $env:USERNAME } catch { }
try { [Console]::CursorVisible = $false } catch { }

# ─────────────────────────────────────────────────────────────────────────────
# 1. Petites briques UI (animations, couleurs, mise en forme)
# ─────────────────────────────────────────────────────────────────────────────
function Wait { param([int]$Ms) if (-not $Fast) { Start-Sleep -Milliseconds $Ms } }

function fmt1 { param([double]$v) return $v.ToString('N1', $script:CI) }
function fmt0 { param([double]$v) return $v.ToString('N0', $script:CI) }

# Texte tape lettre par lettre (effet machine a ecrire)
function Write-Type {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray,
          [int]$Speed = 9, [switch]$NoNewLine, [switch]$Italic)
    $Text = Fix $Text
    if ($script:VT -and $Italic) { Write-Host -NoNewline "$script:ESC[3m" }
    foreach ($ch in $Text.ToCharArray()) {
        Write-Host -NoNewline -ForegroundColor $Color $ch
        if (-not [char]::IsWhiteSpace($ch)) { Wait $Speed } else { Wait 2 }
    }
    if ($script:VT -and $Italic) { Write-Host -NoNewline "$script:ESC[23m" }
    if (-not $NoNewLine) { Write-Host '' }
}

# Banniere ASCII avec degrade vertical ligne par ligne (nuances de bleu)
# Rendu double securite : ANSI 24 bits si le terminal l'interprete, sinon
# ConsoleColor en secours sur le meme Write-Host. Certains hotes (VS Code...)
# avalent les sequences ANSI et afficheraient une banniere blanche : la
# couleur console pose alors le degrade bleu a la place.
function Write-Banner {
    param([string[]]$Lines, [int]$Delay = 45)
    $n = $Lines.Count
    # Degrade a 4 couleurs d'ancrage, interpolees ligne par ligne :
    # plus clair qu'avant en haut, plus fonce en bas, coeur inchange.
    $ramp = @(
        @(175,230,255),   # bleu tres clair (ligne du haut)
        @(110,200,255),   # bleu clair (comme avant)
        @(0,40,120),      # bleu profond (comme avant)
        @(0,8,35)         # bleu nuit tres fonce (ligne du bas)
    )
    # Approximation ConsoleColor du degrade bleu (clair en haut, fonce en bas)
    $ccPal = @('Cyan','Cyan','DarkCyan','Blue','Blue','DarkBlue')
    for ($i = 0; $i -lt $n; $i++) {
        $t = 0; if ($n -gt 1) { $t = $i / ($n - 1) }
        $cc = $ccPal[[int][Math]::Round($t * ($ccPal.Count - 1))]
        if ($script:VT) {
            $pos = $t * ($ramp.Count - 1)
            $k = [int][Math]::Floor($pos); if ($k -gt $ramp.Count - 2) { $k = $ramp.Count - 2 }
            $f = $pos - $k
            $r = [int][Math]::Round($ramp[$k][0] + $f * ($ramp[$k+1][0] - $ramp[$k][0]))
            $g = [int][Math]::Round($ramp[$k][1] + $f * ($ramp[$k+1][1] - $ramp[$k][1]))
            $b = [int][Math]::Round($ramp[$k][2] + $f * ($ramp[$k+1][2] - $ramp[$k][2]))
            Write-Host -NoNewline -ForegroundColor $cc "$script:ESC[38;2;$r;$g;${b}m"
            Write-Host -NoNewline -ForegroundColor $cc $Lines[$i]
            Write-Host -ForegroundColor $cc "$script:ESC[0m"
        } else {
            Write-Host -ForegroundColor $cc $Lines[$i]
        }
        Wait $Delay
    }
}

# Police "bloc" 5x5 (meme style que la banniere BONJOUR) pour dessiner
# du texte arbitraire - typiquement le nom de l'utilisateur.
$script:Font = @{
    'A' = @(' ### ','#   #','#####','#   #','#   #')
    'B' = @('#### ','#   #','#### ','#   #','#### ')
    'C' = @(' ####','#    ','#    ','#    ',' ####')
    'D' = @('#### ','#   #','#   #','#   #','#### ')
    'E' = @('#####','#    ','#### ','#    ','#####')
    'F' = @('#####','#    ','#### ','#    ','#    ')
    'G' = @(' ####','#    ','#  ##','#   #',' ####')
    'H' = @('#   #','#   #','#####','#   #','#   #')
    'I' = @('#####','  #  ','  #  ','  #  ','#####')
    'J' = @('    #','    #','    #','#   #',' ### ')
    'K' = @('#   #','#  # ','###  ','#  # ','#   #')
    'L' = @('#    ','#    ','#    ','#    ','#####')
    'M' = @('#   #','## ##','# # #','#   #','#   #')
    'N' = @('#   #','##  #','# # #','#  ##','#   #')
    'O' = @('#####','#   #','#   #','#   #','#####')
    'P' = @('#### ','#   #','#### ','#    ','#    ')
    'Q' = @('#####','#   #','#   #','#  ##',' ####')
    'R' = @('#### ','#   #','#### ','#  # ','#   #')
    'S' = @(' ####','#    ',' ### ','    #','#### ')
    'T' = @('#####','  #  ','  #  ','  #  ','  #  ')
    'U' = @('#   #','#   #','#   #','#   #',' ### ')
    'V' = @('#   #','#   #','#   #',' # # ','  #  ')
    'W' = @('#   #','#   #','# # #','## ##','#   #')
    'X' = @('#   #',' # # ','  #  ',' # # ','#   #')
    'Y' = @('#   #',' # # ','  #  ','  #  ','  #  ')
    'Z' = @('#####','   # ','  #  ',' #   ','#####')
    '0' = @('#####','#  ##','# # #','##  #','#####')
    '1' = @('  #  ',' ##  ','  #  ','  #  ',' ### ')
    '2' = @('#### ','    #',' ### ','#    ','#####')
    '3' = @('#### ','    #',' ### ','    #','#### ')
    '4' = @('#   #','#   #','#####','    #','    #')
    '5' = @('#####','#    ','#### ','    #','#### ')
    '6' = @(' ####','#    ','#### ','#   #',' ####')
    '7' = @('#####','    #','   # ','  #  ','  #  ')
    '8' = @(' ### ','#   #',' ### ','#   #',' ### ')
    '9' = @(' ### ','#   #',' ####','    #',' ### ')
    '!' = @('  #  ','  #  ','  #  ','     ','  #  ')
    '?' = @('#### ','    #','  ## ','     ','  #  ')
    '-' = @('     ','     ',' ### ','     ','     ')
    '_' = @('     ','     ','     ','     ','#####')
    '.' = @('     ','     ','     ','     ','  #  ')
}

# Transforme un texte en lignes de banniere bloc (glyphes 5x5, espace 2)
function New-BlockText {
    param([string]$Text)
    $rows = @('','','','','')
    $sepDone = $true
    foreach ($c in $Text.ToUpper().ToCharArray()) {
        if ([char]::IsWhiteSpace($c)) {
            for ($i = 0; $i -lt 5; $i++) { $rows[$i] += '     ' }
            $sepDone = $true
            continue
        }
        $glyph = $script:Font[[string]$c]
        if (-not $glyph) { $glyph = $script:Font['?'] }
        if (-not $sepDone) { for ($i = 0; $i -lt 5; $i++) { $rows[$i] += '  ' } }
        $sepDone = $false
        for ($i = 0; $i -lt 5; $i++) { $rows[$i] += $glyph[$i] }
    }
    return $rows
}

# Ligne de progression animee (spinner Braille, facon docker pull)
function Invoke-Step {
    param([string]$Label, [int]$Ms = 600)
    $Label = Fix $Label
    $frames = $Ch.Spinner
    $sw     = [System.Diagnostics.Stopwatch]::StartNew()
    $i      = 0
    if ($Fast) { $Ms = 0 }
    do {
        Write-Host -NoNewline -ForegroundColor DarkCyan ("`r  {0} {1}  " -f $frames[$i % $frames.Count], $Label)
        Start-Sleep -Milliseconds 80
        $i++
    } while ($sw.ElapsedMilliseconds -lt $Ms)
    Write-Host -NoNewline ("`r" + (' ' * ($Label.Length + 10)) + "`r")
    Write-Host -ForegroundColor Green ('  ' + $Ch.Check + ' ' + $Label)
}

# Titre de section
function Write-Section {
    param([string]$Title)
    $Title = Fix $Title
    Write-Host ''
    Write-Host -NoNewline -ForegroundColor Cyan ('  ' + $Ch.Gem + ' ')
    Write-Host -NoNewline -ForegroundColor White $Title
    $rep = 52 - $Title.Length; if ($rep -lt 3) { $rep = 3 }
    Write-Host -ForegroundColor DarkGray (' ' + $Ch.Line + ' ' + ($Ch.Line * $rep))
}

# Jauge animee (barre qui se remplit + compteur de pourcentage)
function Invoke-Gauge {
    param([string]$Label, [int]$Pct, [string]$Detail, [int]$W = 22, [switch]$Inverse)
    $Detail = Fix $Detail
    $pct = [Math]::Min([Math]::Max($Pct, 0), 100)
    $steps = @()
    if ($Fast -or $pct -le 5) { $steps = @($pct) }
    else {
        $steps += 0
        for ($p = 5; $p -lt $pct; $p += 5) { $steps += $p }
        $steps += $pct
    }
    foreach ($p in $steps) {
        $filled = [int][Math]::Round($W * $p / 100)
        $col = 'Green'; if ($p -ge 80) { $col = 'Red' } elseif ($p -ge 55) { $col = 'DarkYellow' }
        if ($Inverse) { $col = 'Green'; if ($p -le 20) { $col = 'Red' } elseif ($p -le 40) { $col = 'DarkYellow' } }
        # Etat intermediaire : jaune-orange 24 bits quand l'ANSI passe,
        # sinon repli ConsoleColor DarkYellow (plus orange que Yellow).
        $amb = ''; $rst = ''
        if ($script:VT) {
            $rst = "$script:ESC[0m"
            if ($col -eq 'DarkYellow') { $amb = "$script:ESC[38;2;255;170;0m" }
        }
        Write-Host -NoNewline ("`r  {0,-9} " -f $Label)
        Write-Host -NoNewline -ForegroundColor DarkGray '['
        Write-Host -NoNewline -ForegroundColor $col ($amb + ($Ch.Block * $filled) + ($Ch.Empty * ($W - $filled)) + $rst)
        Write-Host -NoNewline -ForegroundColor DarkGray ']'
        Write-Host -NoNewline -ForegroundColor $col ($amb + (' {0,3}%' -f $p) + $rst)
        Wait 25
    }
    Write-Host -ForegroundColor DarkGray ('   ' + $Detail)
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Collecte des donnees (rapide, avant l'affichage)
# ─────────────────────────────────────────────────────────────────────────────
$name     = $env:USERNAME; if (-not $name) { $name = [Environment]::UserName }
$now      = Get-Date
$dateStr  = $now.ToString('dddd d MMMM yyyy', $script:CI)
$timeStr  = $now.ToString('HH:mm:ss', $script:CI)

$os = Get-CimInstance -ClassName Win32_OperatingSystem
if (-not $os) { $os = Get-WmiObject -Class Win32_OperatingSystem }
$cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$winName = $os.Caption -replace '^Microsoft\s+', ''
$displayVersion = ''
if ($cv.DisplayVersion) { $displayVersion = $cv.DisplayVersion }
elseif ($cv.ReleaseId) { $displayVersion = $cv.ReleaseId }
$build = '{0}.{1}' -f $cv.CurrentBuild, $cv.UBR

# RAM
$ramTotalKb = [double]$os.TotalVisibleMemorySize
$ramFreeKb  = [double]$os.FreePhysicalMemory
$ramPct    = [Math]::Round(100 * ($ramTotalKb - $ramFreeKb) / $ramTotalKb)
$ramUsedGb = [Math]::Round(($ramTotalKb - $ramFreeKb) / 1MB, 1)
$ramTotalGb = [Math]::Round($ramTotalKb / 1MB, 1)

# CPU (2 sondes espacees pour une moyenne plus honnete)
$cpuSamples = @()
foreach ($i in 1..2) {
    $v = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if ($null -ne $v) { $cpuSamples += [double]$v }
    if ($i -eq 1) { Start-Sleep -Milliseconds 350 }
}
$cpuPct = 0
if ($cpuSamples.Count -gt 0) { $cpuPct = [Math]::Round(($cpuSamples | Measure-Object -Average).Average) }

# Disque (lecteur systeme)
$disk   = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive) | Select-Object -First 1
$diskPct = 0; $diskDetail = 'n/a'
if ($disk -and $disk.Size) {
    $diskPct = [Math]::Round(100 * (1 - $disk.FreeSpace / $disk.Size))
    $diskDetail = ('{0} - {1} Go libres sur {2} Go' -f $disk.DeviceID, (fmt0 ($disk.FreeSpace / 1GB)), (fmt0 ($disk.Size / 1GB)))
}

# Batterie (ignoree proprement sur machine de bureau)
$batt = Get-CimInstance -ClassName Win32_Battery
$battPct = $null; $battDetail = ''
if ($batt -and $null -ne $batt.EstimatedChargeRemaining) {
    $battPct = [int]$batt.EstimatedChargeRemaining
    $st = [int]$batt.BatteryStatus
    if ($st -eq 2) { $battDetail = 'branchée - sur secteur' }
    elseif ($st -eq 1) {
        $battDetail = 'sur batterie'
        $rt = [int]$batt.EstimatedRuntime
        if ($rt -gt 0 -and $rt -lt 1440) {
            $battDetail = ('sur batterie - autonomie estimée ~{0} h{1:00}' -f [int][Math]::Floor($rt / 60), ($rt % 60))
        }
    }
    else { $battDetail = 'en charge' }
}

# IP locale : on privilegie l'interface qui porte la route par defaut
# (evite de piger une carte VirtualBox/Hyper-V), sinon premier IPv4 actif.
$netInfo = ''
$ipObj = $null
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object -Property RouteMetric | Select-Object -First 1
if ($route) {
    $ipObj = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1
}
if (-not $ipObj) {
    $ipObj = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' -and $_.InterfaceAlias -notlike 'Loopback*' -and $_.InterfaceAlias -notmatch 'VirtualBox|VMware' } |
        Sort-Object -Property InterfaceAlias | Select-Object -First 1
}
if ($ipObj) { $netInfo = '{0} - {1}' -f $ipObj.IPAddress, $ipObj.InterfaceAlias }
else {
    $nic = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled='True'" | Select-Object -First 1
    if ($nic -and $nic.IPAddress) { $netInfo = [string]($nic.IPAddress | Select-Object -First 1) }
}
if (-not $netInfo) { $netInfo = 'reseau introuvable' }

# Uptime
$boot = $os.LastBootUpTime
if ($boot -is [string]) {
    try { $boot = [System.Management.ManagementDateTimeConverter]::ToDateTime($boot) } catch { $boot = $null }
}
$upStr = ''; $bootStr = ''
if ($boot) {
    $up = (Get-Date) - $boot
    if ($up.Days -gt 0)      { $upStr = '{0} j {1} h {2} min' -f $up.Days, $up.Hours, $up.Minutes }
    elseif ($up.Hours -gt 0) { $upStr = '{0} h {1} min' -f $up.Hours, $up.Minutes }
    else                     { $upStr = '{0} min' -f $up.Minutes }
    $bootStr = $boot.ToString((Fix 'dddd d MMMM à HH\hmm'), $script:CI)
}

# ── Appls les plus utilisees : UserAssist, sinon FeatureUsage ─────────────────
$script:PrettyApps = @{
    'CHROME'='Google Chrome';        'MSEDGE'='Microsoft Edge';      'FIREFOX'='Mozilla Firefox'
    'BRAVE'='Brave';                'OPERA'='Opera';                'VIVALDI'='Vivaldi'
    'CODE'='Visual Studio Code';    'WINWORD'='Microsoft Word';      'EXCEL'='Microsoft Excel'
    'POWERPNT'='PowerPoint';        'OUTLOOK'='Microsoft Outlook';   'ONENOTE'='OneNote'
    'MSTEAMS'='Microsoft Teams';     'TEAMS'='Microsoft Teams';       'SLACK'='Slack'
    'DISCORD'='Discord';            'ZOOM'='Zoom';                   'SKYPE'='Skype'
    'SPOTIFY'='Spotify';            'VLC'='VLC Media Player';        'ITUNES'='iTunes'
    'STEAM'='Steam';                'EPICGAMESLAUNCHER'='Epic Games'; 'DOCKER DESKTOP'='Docker Desktop'
    'DOCKER'='Docker Desktop';       'GITHUBDESKTOP'='GitHub Desktop'; 'GIT'='Git'
    'PYCHARM64'='PyCharm';          'IDEA64'='IntelliJ IDEA';        'DEVENV'='Visual Studio'
    'NOTEPAD'='Bloc-notes';         'SUBLIME_TEXT'='Sublime Text';   'PYTHON'='Python'
    'PYTHONW'='Python';             'NODE'='Node.js';                'JAVA'='Java'; 'JAVAW'='Java'
    'PHOTOSHOP'='Photoshop';        'ILLUSTRATOR'='Illustrator';     'OBS64'='OBS Studio'
    'BLENDER'='Blender';            'FIGMA'='Figma';                 'WHATSAPP'='WhatsApp'
    'TELEGRAM'='Telegram';          'SIGNAL'='Signal';               'THUNDERBIRD'='Thunderbird'
    'WINRAR'='WinRAR';              '7ZFM'='7-Zip';                  'CALC'='Calculatrice'
    'MSPAINT'='Paint';             'MSPAINT3D'='Paint 3D'
    'SCREENSKETCH'='Snip & Sketch'; 'ACROBATREADER'='Acrobat Reader'
    'WINDOWSNOTEPAD'='Bloc-notes'
}

function Get-PrettyApp {
    param([string]$exe)
    if ($script:PrettyApps.ContainsKey($exe)) { return $script:PrettyApps[$exe] }
    if ($exe.Length -le 3) { return $exe.ToUpper() }
    # Capitalise chaque mot (ex: GOOGLE CHROME -> Google Chrome)
    $words = $exe.ToLower() -split ' '
    return (($words | ForEach-Object { if ($_) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } }) -join ' ')
}

# ROT13 : les noms de valeurs UserAssist sont encodes ainsi
function Convert-Rot13 {
    param([string]$s)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $s.ToCharArray()) {
        $o = [int]$c
        if     ($o -ge 97 -and $o -le 122) { $null = $sb.Append([char]((($o - 97 + 13) % 26) + 97)) }
        elseif ($o -ge 65 -and $o -le 90)  { $null = $sb.Append([char]((($o - 65 + 13) % 26) + 65)) }
        else                              { $null = $sb.Append($c) }
    }
    return $sb.ToString()
}

function Get-TopApps {
    param([int]$Days = 30, [int]$Top = 12)
    $result = [pscustomobject]@{ Source = ''; Apps = @() }
    $noise = @('SVCHOST','CONHOST','CSRSS','DLLHOST','RUNTIMEBROKER','TASKHOSTW','TASKHOSTEX',
        'WERFAULT','WERFAULTSECURE','SEARCHINDEXER','SEARCHPROTOCOLHOST','SEARCHFILTERHOST',
        'SHELLEXPERIENCEHOST','STARTMENUEXPERIENCEHOST','WINLOGON','WININIT','SERVICES','LSASS',
        'SMSS','FONTDRVHOST','DWM','SIHOST','CTFMON','WUDFHOST','MSMPENG','MOBSYNC','AUDIODG',
        'BACKGROUNDTASKHOST','RUNDLL32','MSIEXEC','WMIPRVSE','CMD','POWERSHELL','PWSH',
        'WSCRIPT','CSCRIPT','EXPLORER','FILE EXPLORER','MSDT','SPR','MSEDGEWEBVIEW2')

    # 1) UserAssist : compteur REEL de lancements de l'Explorateur (menu
    #    Demarrer, barre des taches, raccourcis). Noms de valeurs encodes
    #    en ROT13 ; chaque valeur est un blob de 72 octets : nb de
    #    lancements a +4, dernier lancement (FILETIME) a +60.
    #    NB : Prefetch n'est plus decodable sur Win11 24H2+ (format SCCA
    #    change) ; UserAssist est lisible sans admin et voit Firefox.
    $ua = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
    $raw = @()
    if (Test-Path $ua) {
        $cutoffFt = [Int64]((Get-Date).AddDays(-$Days)).ToFileTime()
        foreach ($g in (Get-ChildItem $ua)) {
            $ck = Join-Path $g.PSPath 'Count'
            if (-not (Test-Path $ck)) { continue }
            $k = Get-Item $ck
            foreach ($vn in $k.GetValueNames()) {
                $dec = Convert-Rot13 $vn
                if (-not $dec -or $dec -match '^UEME_') { continue }
                $b = $k.GetValue($vn)
                if (-not ($b -is [byte[]]) -or $b.Length -lt 68) { continue }
                $runs = [BitConverter]::ToUInt32($b, 4)
                $ft   = [BitConverter]::ToUInt64($b, 60)
                if ($runs -lt 1 -or $ft -lt $cutoffFt) { continue }
                # Nettoyage du nom : AUMID empaquete, chemin ou raccourci .lnk
                $base = $dec
                if ($dec -match '!') { $base = ($dec -split '!')[0] -replace '_[0-9A-Za-z]{13}$','' }
                $clean = ($base -split '\\')[-1] -replace '\.(lnk|exe)$',''
                if ($clean -notmatch ' ') { $clean = ($clean -split '\.')[-1] }
                $clean = $clean.Trim().ToUpper()
                if ($clean -and $clean -notmatch '^[A-F0-9]{16}$' -and ($noise -notcontains $clean)) {
                    # Nom mis en forme AVANT le groupage : les alias d'une
                    # meme appli (ex: NOTEPAD et WINDOWSNOTEPAD) fusionnent.
                    $raw += [pscustomobject]@{ Name = (Get-PrettyApp $clean); Count = [int]$runs }
                }
            }
        }
    }
    if ($raw.Count -gt 0) {
        $apps = $raw |
            Group-Object -Property Name |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = ($_.Group | Measure-Object -Property Count -Sum).Sum } } |
            Sort-Object Count -Descending |
            Select-Object -First $Top
        $result.Source = (Fix "compteur UserAssist de l'Explorateur - actives ces $Days derniers jours (lancements réels, cumul)")
        $result.Apps = @($apps)
        return $result
    }

    # 2) Repli : usage cumule consigne par l'Explorateur (FeatureUsage)
    $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppLaunch'
    if (Test-Path $regPath) {
        $key = Get-Item $regPath
        $entries = foreach ($vn in $key.GetValueNames()) {
            # Applis empaquetees (ex: Microsoft.WindowsNotepad_8wekyb3d8bbwe!App) :
            # garder la partie avant '!' sans l'identifiant editeur (sinon on
            # obtient un nom vide du style "App").
            $base = $vn
            if ($vn -match '!') { $base = ($vn -split '!')[0] -replace '_[0-9A-Za-z]{13}$','' }
            $clean = (($base -split '[\\!#]')[-1] -replace '\.exe$','' -replace '_[0-9A-Za-z]{10,}$','')
            $clean = ($clean -split '\.')[-1]
            # Exclure les identifiants hashes (ex: 308046B0AF4A39CB)
            if ($clean -and $clean -notmatch '^[A-F0-9]{8}-' -and $clean -notmatch '^[A-F0-9]{16}$') {
                [pscustomobject]@{ Name = $clean.Trim().ToUpper(); Count = [int]($key.GetValue($vn)) }
            }
        }
        $apps = $entries |
            Where-Object { $noise -notcontains $_.Name } |
            ForEach-Object { [pscustomobject]@{ Name = (Get-PrettyApp $_.Name); Count = $_.Count } } |
            Group-Object -Property Name |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = ($_.Group | Measure-Object -Property Count -Sum).Sum } } |
            Sort-Object Count -Descending |
            Select-Object -First $Top
        $result.Source = (Fix 'registre FeatureUsage (lancements cumulés - approximation sans la fenêtre de 30 jours)')
        $result.Apps = @($apps)
    }
    return $result
}

$appData = Get-TopApps -Days 30 -Top 12

# ─────────────────────────────────────────────────────────────────────────────
# 3. Depart : banniere + sequence de chargement facon docker
# ─────────────────────────────────────────────────────────────────────────────
$banner = @(
'####   #####  #   #      #  #####  #   #  #### '
'#   #  #   #  ##  #      #  #   #  #   #  #   #'
'####   #   #  # # #      #  #   #  #   #  #### '
'#   #  #   #  #  ##  #   #  #   #  #   #  #  # '
'####   #####  #   #   ###   #####   ###   #   #'
)
Write-Host ''
# Bandeau double trait gris au-dessus de la banniere
$bannerW = ($banner | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
$band = $Ch.DLine * $bannerW
Write-Host -ForegroundColor DarkGray $band
Write-Banner -Lines $banner -Delay 45
# Bandeau deux lignes d'etoiles gris sous la banniere
$stars = '*' * $bannerW
Write-Host -ForegroundColor DarkGray $stars
Write-Host -ForegroundColor DarkGray $stars

Write-Host ''
Invoke-Step -Label 'Réveil des capteurs système' -Ms 550
Invoke-Step -Label 'Analyse de tes applis du mois écoulé' -Ms 650
Invoke-Step -Label 'Sondage CPU, RAM et disque' -Ms 500
Write-Host ''

# ─────────────────────────────────────────────────────────────────────────────
# 4. Message de bienvenue (effet machine a ecrire)
# ─────────────────────────────────────────────────────────────────────────────
Write-Type -Text 'Bonjour ' -NoNewLine
Write-Type -Text $name -Color Cyan -NoNewLine
Write-Type -Text ','
Write-Type -Text 'Nous sommes le ' -NoNewLine
Write-Type -Text $dateStr -Color Cyan -NoNewLine
Write-Type -Text ', et il est ' -NoNewLine
Write-Type -Text $timeStr -Color Cyan -NoNewLine
Write-Type -Text '.'
Write-Type -Text "Je te souhaite une bonne expérience numérique, pleine d'inédit !" -Color DarkCyan -Italic
Write-Type -Text "Sache que je suis ton fidèle dévoué, et prêt à réaliser l'impossible avec toi !" -Color DarkCyan -Italic

# ─────────────────────────────────────────────────────────────────────────────
# 5. Pour infos
# ─────────────────────────────────────────────────────────────────────────────
Write-Section -Title 'TA VERSION DE WINDOWS'
Write-Type -Text ('  {0} {1} ({2}) - build {3}' -f $Ch.Star, $winName, $displayVersion, $build) -Color Cyan -Speed 4

Write-Section -Title 'TOP 12 APPLIS LES PLUS LANCÉES DEPUIS UN MOIS'
$apps = @($appData.Apps)
if ($apps.Count -gt 0) {
    $max = ($apps | Measure-Object -Property Count -Maximum).Maximum
    # Degrade violet-bleu -> bleu -> bleu-vert -> cyan -> gris sur le classement
    $rankColors = @('DarkMagenta','Blue','DarkCyan','Cyan','Gray','DarkGray','DarkGray','DarkGray',
                    'DarkGray','DarkGray','DarkGray','DarkGray')
    $rank = 0
    foreach ($a in $apps) {
        $pretty = Fix $a.Name
        $col = $rankColors[[Math]::Min($rank, 11)]
        $barLen = [int][Math]::Round(14 * $a.Count / [double]$max); if ($barLen -lt 1) { $barLen = 1 }
        Write-Host -NoNewline ("  {0,2}. " -f ($rank + 1))
        Write-Host -NoNewline -ForegroundColor $col ("{0,-24}" -f $pretty)
        Write-Host -NoNewline -ForegroundColor $col ($Ch.Block * $barLen)
        Write-Host -ForegroundColor DarkGray ((' ' + $a.Count + ' ' + (Fix 'lancements')))
        $rank++
        Wait 70
    }
    Write-Host -ForegroundColor DarkGray ('  ' + $Ch.Corner + ' ' + (Fix ('source : {0}' -f $appData.Source)))
} else {
    Write-Host -ForegroundColor DarkGray (Fix '  aucune donnée d''usage trouvée')
}

Write-Section -Title 'POINT SANTÉ DE TA MACHINE'
Invoke-Gauge -Label 'RAM'      -Pct $ramPct  -Detail ("{0} Go utilisés sur {1} Go" -f (fmt1 $ramUsedGb), (fmt1 $ramTotalGb))
Invoke-Gauge -Label 'CPU'      -Pct $cpuPct  -Detail (Fix 'charge instantanée (moyenne de 2 sondes)')
Invoke-Gauge -Label 'DISQUE'   -Pct $diskPct -Detail $diskDetail
if ($null -ne $battPct) {
    Invoke-Gauge -Label 'BATTERIE' -Pct $battPct -Detail $battDetail -Inverse
} else {
    Write-Host -ForegroundColor DarkGray (('  {0,-9} ' -f 'BATTERIE') + (Fix 'non détectée (station de bureau ?)'))
}
Write-Host -NoNewline ('  {0,-9} ' -f 'IP')
Write-Host -ForegroundColor Cyan (Fix $netInfo)
Wait 80
Write-Host -NoNewline ('  {0,-9} ' -f 'UPTIME')
if ($upStr) {
    Write-Host -NoNewline -ForegroundColor Cyan $upStr
    Write-Host -ForegroundColor DarkGray ('   (' + (Fix ('démarré le {0}' -f $bootStr)) + ')')
} else {
    Write-Host -ForegroundColor DarkGray 'n/a'
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Fin
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Type -Text (Fix 'Système prêt. À toi de jouer,') -Color Green -Speed 12
# Banniere du nom : meme mise en forme que BONJOUR (bandeau, degrade bleu, etoiles)
$nameLines = @(New-BlockText -Text ($name + ' !'))
if ($nameLines[0]) {
    $nw = ($nameLines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    Write-Host -ForegroundColor DarkGray ($Ch.DLine * $nw)
    Write-Banner -Lines $nameLines -Delay 45
    $nstars = '*' * $nw
    Write-Host -ForegroundColor DarkGray $nstars
    Write-Host -ForegroundColor DarkGray $nstars
}
if ($script:Repaired) {
    Write-Host -ForegroundColor DarkGray (Fix '  (fichier ré-encodé en UTF-8 avec BOM : les accents seront natifs au prochain lancement)')
}
Write-Host ''
Write-Host -ForegroundColor DarkGray ('  bonjour-systeme.ps1 ' + $Ch.Dot + ' ' + (Fix '100% local - aucune donnée ne quitte ta machine'))

try { [Console]::CursorVisible = $true } catch { }