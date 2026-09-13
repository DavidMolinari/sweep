# Sweep

[English](README.md) | **Français**

Sweep est un nettoyeur de disque natif macOS. Il analyse les caches, les
journaux, la corbeille, les caches de développement et les gros fichiers, puis
déplace vers la corbeille ce que vous sélectionnez. Aucune suppression
définitive, à une exception près : vider la corbeille, action que vous
confirmez explicitement.

Écrit en SwiftUI avec Swift Package Manager, macOS 14+, sans dépendance tierce,
sans télémétrie, sans réseau.

[![CI](https://github.com/DavidMolinari/sweep/actions/workflows/ci.yml/badge.svg)](https://github.com/DavidMolinari/sweep/actions/workflows/ci.yml)
[![Licence : MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Plateforme : macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-black.svg)

## Téléchargement

Prenez le DMG sur la **[dernière release](https://github.com/DavidMolinari/sweep/releases/latest)**, ouvrez-le et glissez **Sweep** dans **Applications**.

> L'app est signée ad-hoc (pas encore notariée) : au premier lancement, faites un clic droit sur Sweep dans Applications puis **Ouvrir**.

Pour la compiler vous-même : `make run` compile et lance l'app.

## Captures d'écran

| Clair | Sombre |
| --- | --- |
| ![Fenêtre principale de Sweep, apparence claire](docs/assets/sweep-light.png) | ![Fenêtre principale de Sweep, apparence sombre](docs/assets/sweep-dark.png) |

## Fonctionnalités

- **Caches** — contenu de `~/Library/Caches`, mesuré en blocs alloués (espace
  réellement occupé, pas la taille logique).
- **Journaux** — contenu de `~/Library/Logs`.
- **Corbeille** — contenu de `~/.Trash`. Nettoyer cette catégorie est la seule
  suppression définitive de l'app.
- **Caches de développement** — DerivedData et DeviceSupport de Xcode,
  CoreSimulator, Homebrew, CocoaPods, SwiftPM, pip, npm/yarn/pnpm, Gradle,
  Cargo, Go et Hugging Face.
- **Gros fichiers** — analyse Téléchargements, Bureau, Documents, Images,
  Films et Musique, ou un dossier choisi. Seuil de taille configurable, filtre
  « plus de 6 mois », tri par taille décroissante. Les sous-arbres projets et
  les paquets sensibles sont exclus du scan : ils ne sont jamais proposés.
- **Signalements de prudence** — archives, images disque, bases de données,
  applications en cours d'exécution, symboles de débogage et modèles IA sont
  signalés et décochés par défaut. Les gros fichiers sont toujours décochés par
  défaut : rien n'est supprimé sans un choix explicite, ligne par ligne.

## Prérequis

- macOS 14 (Sonoma) ou ultérieur
- Xcode 15 ou ultérieur pour compiler depuis les sources (Swift 5.9)

## Compiler et lancer

```sh
git clone https://github.com/DavidMolinari/sweep.git
cd sweep
make run
```

`make run` compile le binaire release, fabrique `dist/Sweep.app`, le signe en
ad-hoc et l'ouvre. Le binaire est compilé **universel** (arm64 + x86_64) quand
la chaîne d'outils le permet, avec repli sur l'architecture native sinon. Pour
fabriquer le bundle sans le lancer :

```sh
make app
```

### Cibles Make

| Cible | Effet |
| --- | --- |
| `make build` | Compile le binaire release avec SwiftPM |
| `make app` | Fabrique et signe en ad-hoc `dist/Sweep.app` |
| `make run` | `make app` puis ouvre l'app |
| `make install` | Copie l'app dans `/Applications` |
| `make release` | Auto-tests, puis zip de l'app (`LICENSE` et `README.md` inclus) avec empreinte SHA-256 dans `dist/` |
| `make clean` | Supprime les produits de compilation et `dist/` |

### Installation

```sh
make install
```

Le bundle est copié dans `/Applications/Sweep.app`. Si `/Applications` n'est
pas accessible en écriture à votre utilisateur, la commande s'arrête en
indiquant de la relancer avec `sudo`. Les versions publiées sont signées en
ad-hoc, pas notariées : une copie téléchargée peut nécessiter un clic droit →
**Ouvrir** au premier lancement.

## Modèle de sûreté

Sweep est conçu pour que le pire scénario soit un fichier dans la corbeille.

### Jamais proposé à la suppression

- **Sous-arbres projets.** Pendant l'analyse des gros fichiers, un dossier qui
  contient un marqueur de projet (`.git`, `package.json`, `Cargo.toml`,
  `go.mod`, `pyproject.toml`, `Package.swift`, `pom.xml`, `*.xcodeproj`,
  `*.xcworkspace`, `CMakeLists.txt`, `Dockerfile`…) n'est pas parcouru.
- **Paquets et conteneurs sensibles.** `.app`, `.framework`, `.bundle`,
  `.plugin`, `.kext`, photothèques (`*.photoslibrary`…), bibliothèques iMovie/TV
  et Final Cut, disques virtuels et VM (`.sparsebundle`, `.sparseimage`,
  `.vmwarevm`, `.utm`, `.qcow2`, `.vmdk`…) sont ignorés.
- **Emplacements protégés.** Le nettoyeur refuse `/`, `~`, `~/Library`,
  `~/Documents`, `~/Desktop`, `~/Downloads`, `/Applications`, `/System`,
  `/Library`, `/private`, `/usr`, `/bin`… ainsi que les sous-arbres sensibles
  tels que `~/Library/Containers`, `Application Support`, `Mail`, `Safari`,
  `Keychains` et `CloudStorage`.
- **Liens symboliques.** Ils ne sont jamais suivis, ni à l'analyse ni au
  nettoyage.
- **Racines personnalisées.** Choisir `~/Library`, `~/.Trash`, `/Applications`,
  `/System`… comme racine d'analyse est refusé par une alerte, et ces zones ne
  sont jamais parcourues, même si un chemin y menait.

Chaque élément scanné porte sa racine d'analyse. Le nettoyeur refuse tout
élément qui n'en est pas un descendant strict, même après résolution des liens
symboliques, et refuse les éléments marqués protégés même si l'interface en
présentait. Le mode de suppression est déterminé par la catégorie dans le code,
jamais par l'interface.

### Déplacé vers la corbeille (récupérable)

Caches, journaux, caches de développement et gros fichiers sont déplacés via
`FileManager.trashItem`. Sur APFS le déplacement est instantané ; l'espace est
libéré quand vous videz la corbeille, ou plus tard depuis la catégorie
**Corbeille** de l'app.

### La seule action définitive

Vider la corbeille. C'est réservé à la catégorie Corbeille, annoncé comme
irréversible dans la feuille de confirmation, et seuls les chemins situés dans
`~/.Trash` peuvent être supprimés. Rien d'autre dans l'app ne supprime
définitivement.

### Garde-fous automatiques

```sh
./dist/Sweep.app/Contents/MacOS/Sweep --selftest
```

Douze vérifications s'exécutent sur des fixtures temporaires et nettoient
derrière elles :

```
move-to-trash:      removed=1 failures=0 gone=true
outside-root:       removed=0 failures=1 intact=true
trash-outside:      removed=0 failures=1 intact=true
empty-trash:        removed=1 failures=0 gone=true permanent=true
symlink-root:       issue=symbolic link root refused
trash-resolved:     removed=0 failures=1 intact=true
large-roots:        slash=true users=true volumes=true home=true library=true child=true
case-fold:          removed=0 failures=1 intact=true
trash-app-protected:safety=true removed=0 failures=1 intact=true
select-all-preserve:safe=true flagged=true
select-all-clear:   allCleared=true
selftest:           0 failures
```

Le code de sortie vaut 0 seulement si toutes passent (la dernière ligne
indique `0 failures`) ; `case-fold` est ignoré sur un volume sensible à la
casse. La CI l'exécute à chaque push.

## Accès complet au disque

macOS protège certains emplacements via TCC. Sans Accès complet au disque,
Sweep ne peut pas lister :

- `~/.Trash` — vider la corbeille suppose de pouvoir la lire ;
- les bibliothèques et caches appartenant à d'autres apps (Mail, Safari,
  Messages…).

Dans ce cas, la catégorie affiche un échec explicite avec un bouton
**Ouvrir l'accès complet au disque…** au lieu de faire croire que le dossier
est vide.

Recommandé juste après l'installation :

1. Réglages Système → Confidentialité et sécurité → **Accès complet au disque**.
2. Ajouter `Sweep.app` (depuis `/Applications`, ou `dist/Sweep.app` pour une
   compilation locale) et l'activer.
3. Relancer l'analyse de la catégorie.

Les compilations étant signées en ad-hoc et non avec un Developer ID, macOS
peut redemander la permission après un `make app` qui remplace le binaire —
retirez puis rajoutez l'app si un scan signale de nouveau des permissions
refusées.

## Langues

L'interface est localisée via `Support/Resources/*.lproj/Localizable.strings`
(clés en anglais) : **anglais** (base), **français**, **allemand** et
**espagnol**. L'app suit la langue du système ; pour forcer une langue par
application : Réglages Système → Général → Langue et région → Applications.

Pour ajouter une langue : dupliquer `Support/Resources/en.lproj`, garder les
fichiers synchronisés, traduire les valeurs, ajouter la langue à
`CFBundleLocalizations` dans `Support/Info.plist`, puis `make app`.

## Ligne de commande

Le bundle de l'app est aussi un petit outil headless.

### `--scan`

```sh
./dist/Sweep.app/Contents/MacOS/Sweep --scan [catégorie ...]
```

Catégories : `caches`, `logs`, `trash`, `developer`, `largeFiles`. Sans
catégorie, toutes sont analysées. La sortie contient une ligne de synthèse par
catégorie (séparateur tabulation), puis les 12 premiers éléments avec leur
niveau de sûreté :

```
caches	~/Library/Caches	42 items	123456789 bytes	1.8s
   [safe] selected=true 10485760	/Users/me/Library/Caches/example
   [caution:app-running] selected=false 5242880	/Users/me/Library/Caches/other
```

Code de sortie 0 en cas de succès, 1 pour une catégorie inconnue. Le scan est
en lecture seule : `--scan` ne supprime et ne déplace rien.

### `--selftest`

Exécute les douze tests de garde-fous décrits plus haut et sort avec 0
(succès) ou 1 (échec). Utile avant et après une compilation de release, et en
CI.

## Organisation du projet

```
Sources/Sweep/
  SweepApp.swift          point d'entrée SwiftUI, commandes de menu
  HeadlessMode.swift      --scan et --selftest
  Models/                 catégories, éléments scannés, niveaux de sûreté, AppModel
  Services/               DiskScanner (lecture), Cleaner (corbeille / vidage)
  Views/                  sidebar, détail de catégorie, confirmation et rapport
Support/
  Info.plist              métadonnées du bundle (langues, descriptions d'accès)
  Resources/*.lproj/      chaînes en, fr, de, es
  Branding/               icône de l'app (AppIcon.icns), optionnelle à la compilation
Makefile                  compilation, bundle, installation, release
docs/                     guide de release et captures d'écran
```

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md), le
[Code de conduite](CODE_OF_CONDUCT.md) et [SECURITY.md](SECURITY.md) pour les
signalements privés de vulnérabilités. Les invariants de sûreté listés dans
CONTRIBUTING sont à lire avant de toucher à `Services/`.

## Licence

[MIT](LICENSE) © 2026 David Molinari.

Sweep n'a aucune dépendance tierce : uniquement des frameworks Apple (SwiftUI,
AppKit, Foundation) et des SF Symbols référencés par nom. Voir
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) pour le détail.
