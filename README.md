# Bonjour, Système ! 👋

![Windows](https://img.shields.io/badge/OS-Windows%2010%20%7C%2011-0078D6?logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![100% local](https://img.shields.io/badge/Donn%C3%A9es-100%25%20local-success)
![Pas d'admin requis](https://img.shields.io/badge/Administrateur-non%20requis-informational)

```
####   #####  #   #      #  #####  #   #  #### 
#   #  #   #  ##  #      #  #   #  #   #  #   #
####   #   #  # # #      #  #   #  #   #  #### 
#   #  #   #  #  ##  #   #  #   #  #   #  #  # 
####   #####  #   #   ###   #####   ###   #   #
```

Un petit script PowerShell qui affiche, dans votre terminal, un **brief système animé **

**Pour faire vite, en 2 étapes rapides :**

## Étape 1 : récupérer le projet

 Télécharger en ZIP (le plus simple, aucun logiciel requis)

1. Cliquez sur le bouton vert **`<> Code`** en haut à droite de cette page
2. Choisissez **`Download ZIP`**
3. Décompressez le fichier ZIP (clic droit → *Extraire tout…*)
4. Vous obtenez un dossier `bonjour-systeme-main` contenant le script

---
## Étape 2 : lancer le script

Ouvrez **PowerShell** :

1. Cliquez sur le menu **Démarrer**
2. Tapez `powershell`
3. Cliquez sur **Windows PowerShell**

Déplacez-vous dans le dossier du projet. Par exemple, si vous avez extrait le dossier dans "Téléchargements", copier la commande :

```powershell
Set-Location "$HOME\Downloads"
```

Puis lancez le script :

```powershell
powershell -ExecutionPolicy Bypass -File .\bonjour-systeme.ps1
```

C'est tout ! Regardez le terminal, c'est parti. 🎬

---

## -> PLus d'infos ?

## Ce que le script affiche

- Un message de bienvenue personnalisé avec votre **nom d'utilisateur**, la date et l'heure
- Votre **version de Windows** (édition, version, build)
- Le **top 12 des applications** les plus lancées depuis un mois
- Un **point santé** de la machine : RAM, disque, CPU, batterie
- En bonus : votre **adresse IP locale** et l'**uptime** de la machine

Le tout est **100 % local** : aucune donnée ne quitte votre machine, aucune connexion réseau n'est nécessaire (hormis votre propre réseau local pour afficher l'IP).

---

## Prérequis

| Élément | Détail |
|---|---|
| Système | Windows 10 ou Windows 11 |
| PowerShell | Inclus dans Windows par défaut (version 5.1 ou plus) — rien à installer |
| Droits | Aucun. Le script fonctionne en utilisateur standard, sans administrateur |

> **Vous ne savez pas ce qu'est PowerShell ?** C'est l'outil de ligne de commande installé d'office sur tous les Windows. Vous n'avez rien à installer, il est déjà sur votre machine.

---

### Bonus : mode rapide

Les animations sont jolies, mais si vous êtes pressé, ajoutez le paramètre `-Fast` pour tout afficher instantanément :

```powershell
powershell -ExecutionPolicy Bypass -File .\bonjour-systeme.ps1 -Fast
```

---

## Pourquoi `-ExecutionPolicy Bypass` ?

Bonne question ! 🤓

Par sécurité, Windows ** bloque par défaut** l'exécution de scripts PowerShell téléchargés depuis Internet. C'est une protection contre les scripts malveillants : elle ne concerne que le *lancement* de scripts, jamais votre machine.

L'option `-ExecutionPolicy Bypass` dit à PowerShell :

> "Pour **cette exécution uniquement**, j'autorise ce script précis."

Trois choses importantes à savoir :

1. **C'est temporaire** : l'autorisation ne vaut que le temps de cette commande. Elle ne modifie aucun réglage permanent de Windows.
2. **C'est ciblé** : seul le fichier `bonjour-systeme.ps1` est concerné, pas tous les scripts de votre machine.
3. **Lisez toujours les scripts que vous exécutez** : c'est la règle d'or, quelle que soit la source. Celui-ci est commenté de bout en bout si vous voulez le lire.

---

## Questions fréquentes

<details>
<summary><b>Les accents s'affichent bizarrement (Ã©, â, etc.) au premier lancement</b></summary>

C'est un problème d'encodage bien connu de PowerShell 5.1 avec les fichiers sans BOM. **Le script se répare tout seul** : il détecte le problème et se ré-écrit correctement en UTF-8 avec BOM. Relancez-le une seconde fois, tout s'affichera parfaitement.
</details>

<details>
<summary><b>Je suis sur un PC de bureau et je vois "BATTERIE : non détectée"</b></summary>

C'est normal : votre machine n'a pas de batterie, le script l'indique proprement et passe à la suite.
</details>

<details>
<summary><b>Le script envoie-t-il des données quelque part ?</b></summary>

Non, aucune. Toutes les informations affichées (RAM, disque, applications, IP…) sont lues localement sur votre machine et affichées dans votre terminal. Rien ne sort, rien n'est enregistré.
</details>

<details>
<summary><b>Comment le script connaît-il mes applications les plus utilisées ?</b></summary>

Il lit le compteur `UserAssist` de l'Explorateur Windows : c'est le compteur officiel que Windows utilise pour afficher vos applications "les plus utilisées" dans le menu Démarrer. Il ne s'agit pas d'un suivi caché du script, mais d'une donnée que Windows collecte déjà pour lui-même. Le script se contente de la lire.
</details>
 
---

## Structure du projet

```
bonjour-systeme/
├── bonjour-systeme.ps1   # Le script (seul et unique fichier nécessaire)
├── .gitignore            # Liste des fichiers que Git doit ignorer
└── README.md             # Ce fichier
```

---

*Fait avec ❤️*