# LetsWork — Mise en place du projet

Ce document explique comment installer, compiler et faire évoluer le projet LetsWork.
Les fonctionnalités à développer sont décrites dans [FEATURES.md](FEATURES.md).

---

## Sommaire

1. [Choix techniques](#1-choix-techniques)
2. [Prérequis](#2-prérequis)
3. [Installer les outils](#3-installer-les-outils)
4. [Première installation](#4-première-installation)
5. [Le projet Xcode (project.yml)](#5-le-projet-xcode-projectyml)
6. [Commandes du Makefile](#6-commandes-du-makefile)
7. [Adaptateur média (mediaremote-adapter)](#7-adaptateur-média-mediaremote-adapter)
8. [Autorisations et signature pendant le développement](#8-autorisations-et-signature-pendant-le-développement)
9. [Architecture et conventions](#9-architecture-et-conventions)
10. [Distribution](#10-distribution)
11. [Dépannage](#11-dépannage)

---

## 1. Choix techniques

| Sujet | Choix | Raison |
|---|---|---|
| Langage | **Swift 6** (mode de langage 6, concurrence stricte) | Natif, sûr, sans dépendance d'exécution. |
| Interface | **SwiftUI** pour les vues, **AppKit** pour la fenêtre (`NSPanel`) | SwiftUI ne sait pas créer une fenêtre sans bordure au-dessus de la barre de menus ; AppKit si. |
| État | `@Observable` (framework Observation) | Simple, performant, natif depuis macOS 14. |
| Cible minimale | **macOS 14 Sonoma** | `@Observable`, accès complet EventKit (`requestFullAccessToEvents`), `NSApp.activate()`, `SMAppService`. |
| Langue de développement | **Français** (`developmentLanguage: fr`) | Les textes source sont en français ; dates et heures formatées en français. L'anglais viendra au jalon M4. |
| Projet Xcode | **XcodeGen** (`project.yml` → `.xcodeproj` généré, non versionné) | Projet décrit en texte, lisible, sans conflits de merge sur le `.pbxproj`. |
| Sandbox | **Désactivée** | Un event tap qui absorbe les touches (F2) et le lancement de `/usr/bin/perl` (F1) sont incompatibles avec la sandbox. |
| Distribution | **Developer ID + notarisation**, hors Mac App Store | Imposé par les API privées (MediaRemote, DisplayServices) et l'absence de sandbox. |
| Médias | [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause), sous-module git épinglé sur `v0.7.7` | Seul moyen fiable de lire le « Now Playing » depuis macOS 15.4. |
| Tests | **Swift Testing** (`import Testing`) | Framework de test actuel d'Apple. |

---

## 2. Prérequis

| Outil | Version | Sur ce Mac (26/10/2026) |
|---|---|---|
| macOS | 14 ou plus récent | 27.0.1 ✅ |
| Xcode | 26 ou plus récent | 27.1 (Swift 6.4) ✅ |
| Homebrew | — | installé ✅ |
| XcodeGen | dernière version | 2.46.0 ✅ |
| CMake | ≥ 3.20 (adaptateur média) | 4.4.4 ✅ |
| Certificat Apple Development | requis à partir de M2 (voir section 8) | **aucun installé** |
| Compte Apple Developer | gratuit pour le développement, payant (99 $/an) pour distribuer avec Developer ID | à vérifier |

Un **MacBook Pro avec encoche** est nécessaire pour valider le rendu de l'Island ; sur un écran sans encoche, l'Island est simulée (voir FEATURES.md, F0).

---

## 3. Installer les outils

```bash
brew install xcodegen cmake
```

Puis vérifier :

```bash
xcodegen --version && cmake --version
```

---

## 4. Première installation

Après un `git clone`, récupérer l'adaptateur média et ses propres sous-modules :

```bash
git submodule update --init --recursive
```

Compiler l'adaptateur média, puis générer le projet Xcode depuis `project.yml` :

```bash
make bootstrap
```

Sans adaptateur compilé, le projet se construit quand même : l'app se rabat sur Musique et Spotify (voir section 7).

Compiler et lancer l'app (ferme d'abord l'instance en cours, quelle que soit sa copie) :

```bash
make run
```

Ou ouvrir le projet dans Xcode et lancer avec ⌘R :

```bash
make open
```

> Xcode compile dans son propre dossier (`~/Library/Developer/Xcode/DerivedData`), le Makefile dans `build/DerivedData`. Relancer l'app depuis Spotlight ou le Finder peut ouvrir une copie périmée : utiliser `make run` ou ⌘R.

**Résultat attendu (M1)** :

- l'Island fermée est invisible, confondue avec l'encoche ;
- au survol de l'encoche, elle se déploie et se referme quand la souris s'éloigne : lecteur média si une lecture est connue, sinon date et heure ;
- un clic sur l'Island la garde ouverte ; un clic ailleurs la referme ;
- pendant une lecture, l'Island passe en compact (pochette à gauche, égaliseur à droite) ; à chaque nouvelle piste, le titre s'affiche dessous pendant 3 s ; après une pause, elle se referme au bout de 5 s ;
- **Réglages › Médias** indique la source utilisée : « Now Playing de macOS » (adaptateur) ou « Repli AppleScript » ;
- une icône en forme de capsule apparaît dans la barre de menus, avec **Nouvel événement…** (⌘N), **Réglages…** et **Quitter** ;
- aucune icône dans le Dock.

---

## 5. Le projet Xcode (`project.yml`)

`project.yml` est la **seule source de vérité** du projet : le `.xcodeproj` est régénéré par `make project` et ignoré par git. `Config/Info.plist` et `Config/LetsWork.entitlements` sont eux aussi générés à partir de ce fichier : toute modification se fait dans `project.yml`.

| Réglage | Valeur | Remarque |
|---|---|---|
| `bundleIdPrefix` / `PRODUCT_BUNDLE_IDENTIFIER` | `dev.projects` / `dev.projects.letswork` | |
| `developmentLanguage` | `fr` | |
| `deploymentTarget` | macOS 14.0 | |
| `SWIFT_VERSION` | 6.0 | mode de langage Swift 6 |
| `CODE_SIGN_IDENTITY` | `-` (signature locale ad hoc) | à remplacer avant M2, voir section 8 |
| `DEVELOPMENT_TEAM` | vide | à renseigner avant M2 |
| `ENABLE_HARDENED_RUNTIME` | YES | requis pour la notarisation |
| `LSUIElement` | true | pas d'icône dans le Dock |
| `NSCalendarsFullAccessUsageDescription`, `NSAppleEventsUsageDescription` | textes en français | affichés dans les invites système (F3, F1) |
| Entitlements | `automation.apple-events`, `personal-information.calendars`, pas de sandbox | |
| Cible de tests `LetsWorkTests` | `bundle.unit-test`, `GENERATE_INFOPLIST_FILE: YES` | hébergée par l'app |

> **Sans XcodeGen** : créer le projet dans Xcode (Fichier › Nouveau › Projet › macOS › App, interface SwiftUI) et reporter à la main les réglages ci-dessus, puis y ajouter les dossiers `LetsWork/` et `LetsWorkTests/`.

---

## 6. Commandes du Makefile

| Commande | Effet |
|---|---|
| `make bootstrap` | Première installation : compile l'adaptateur média, puis génère le projet. |
| `make project` | Régénère `LetsWork.xcodeproj` depuis `project.yml`. |
| `make open` | Régénère puis ouvre le projet dans Xcode. |
| `make build` | Compile la configuration Debug dans `build/DerivedData`. |
| `make run` | Compile, quitte l'instance en cours (y compris l'app installée dans Applications) et lance ce build. |
| `make test` | Lance les tests unitaires. |
| `make adapter` | Compile `MediaRemoteAdapter.framework` dans `Vendor/build/` (M1). |

---

## 7. Adaptateur média (mediaremote-adapter)

Depuis macOS 15.4, une application ne peut plus lire directement le framework privé MediaRemote. L'adaptateur fait exécuter un petit framework par `/usr/bin/perl` (binaire système autorisé) et diffuse les infos de lecture en JSON. LetsWork lance `stream --no-diff --micros --debounce=100`, et `send <id>` / `seek <µs>` pour les commandes.

**État actuel** : sous-module `Vendor/mediaremote-adapter` épinglé sur `v0.7.7`, compilé et intégré au build. Validé sur ce Mac (macOS 27.0.1) avec Spotify : titre, pochette, progression et couleur d'accent dès le lancement.

### 7.1 Compiler et tester l'adaptateur

```bash
make adapter
```

Test rapide (les chemins doivent être **absolus** ; code de sortie `0` = l'adaptateur fonctionne sur ce Mac) :

```bash
/usr/bin/perl "$PWD/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$PWD/Vendor/build/MediaRemoteAdapter.framework" test; echo "exit=$?"
```

Lancer une musique ou une vidéo YouTube, puis :

```bash
/usr/bin/perl "$PWD/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$PWD/Vendor/build/MediaRemoteAdapter.framework" get --no-artwork
```

On doit obtenir un JSON avec notamment `bundleIdentifier`, `playing`, `title`, `artist`, `duration`, `elapsedTime`.

### 7.2 Embarquement dans l'app

La phase de build **« Embarquer mediaremote-adapter »** (`scripts/embed-mediaremote-adapter.sh`, déclarée dans `project.yml`) :

- copie `Vendor/build/MediaRemoteAdapter.framework` dans `LetsWork.app/Contents/Frameworks/` et le signe avec le hardened runtime (horodaté en Release) ;
- copie `mediaremote-adapter.pl` dans `LetsWork.app/Contents/Resources/` ;
- si le framework n'a pas été compilé, n'embarque rien et affiche une note dans le journal de build.

Le framework n'est **jamais lié** à l'app : c'est `/usr/bin/perl` qui le charge. Une phase de script, plutôt qu'une dépendance XcodeGen, permet de compiler l'app même sans framework.

### 7.3 Choix de la source au lancement

1. Framework et script présents dans l'app → **adaptateur** (« Now Playing de macOS » dans les réglages).
2. Sinon, ou après deux arrêts de l'adaptateur en moins de 10 s → **repli AppleScript** :
   - lecture des notifications distribuées `com.spotify.client.PlaybackStateChanged` et `com.apple.Music.playerInfo` (sans autorisation) ;
   - au démarrage, lecture de l'état des lecteurs déjà ouverts par AppleScript, **seulement si l'autorisation Automatisation est déjà accordée** (vérifiée sans afficher de demande) ;
   - commandes par AppleScript, uniquement vers une app déjà ouverte (autorisation Automatisation au premier clic) ;
   - limites : sans autorisation, état connu seulement à la prochaine notification (lecture, pause, changement de piste) ; pas de pochette ; vidéos des navigateurs non détectées.

### 7.4 Cycle de vie du processus

L'adaptateur est un processus enfant de l'app. Si l'app est tuée sans se terminer (plantage, arrêt depuis Xcode), il est rattaché à `launchd` et ne s'arrête qu'à sa prochaine écriture. Au démarrage, l'app supprime donc les adaptateurs orphelins lancés depuis sa propre copie (`pkill -P 1 -f <chemin du script>`). Quand l'app sert d'hôte aux tests unitaires, elle ne démarre ni l'Island ni l'adaptateur.

> Le projet indique que son API peut changer entre versions mineures : ne changer de tag (`git -C Vendor/mediaremote-adapter checkout <tag>`) qu'après avoir refait les tests ci-dessus.

---

## 8. Autorisations et signature pendant le développement

| Autorisation | Fonctionnalité | Où l'accorder |
|---|---|---|
| Accessibilité | F2 (event tap) | Réglages Système › Confidentialité et sécurité › Accessibilité |
| Calendriers (accès complet) | F3 | Onglet Calendrier ou Réglages › Calendrier › « Autoriser… », puis › Calendriers |
| Accès complet au disque | F4 (lecture des notifications) | Réglages Système › Confidentialité et sécurité › Accès complet au disque › + › LetsWork |
| Automatisation (Musique, Spotify) | F1, canal de repli | Invite système au premier Apple Event, puis › Automatisation |

- **Calendriers** (M3) : demandés depuis l'onglet Calendrier ou Réglages › Calendrier, jamais au lancement.
- **Accessibilité** (M2) : demandée depuis Réglages › Volume et luminosité › « Autoriser… ». Sans elle, LetsWork n'intercepte rien et les indicateurs de macOS restent affichés. L'app détecte l'autorisation sans redémarrage.
- **Accès complet au disque** (F4) : à ajouter à la main dans Réglages Système, pour la copie de LetsWork que tu lances (build de développement ou app installée). La lecture démarre d'elle-même dans les 10 s.
- **Automatisation** (M1) : seulement pour le repli AppleScript, au premier clic sur un contrôle de lecture.

**Autorisations et builds de développement** : macOS rattache une autorisation à l'*exigence désignée* de la signature. Pour une signature ad hoc, c'est par défaut l'empreinte du binaire : chaque build perdrait l'autorisation Accessibilité (l'app resterait cochée dans la liste sans être reconnue).

En **Debug**, `project.yml` impose donc une exigence fondée sur l'identifiant seul (`OTHER_CODE_SIGN_FLAGS`) :

```text
designated => identifier "dev.projects.letswork"
```

- L'autorisation, accordée une fois, reste valable d'un build Debug à l'autre.
- Contrepartie : pendant le développement, toute app locale signée avec cet identifiant hériterait des autorisations de LetsWork.
- `ENABLE_DEBUG_DYLIB` est désactivé en Debug : sinon ces options de signature s'appliqueraient aussi aux bibliothèques des aperçus SwiftUI et rendraient le bundle invalide.
- Le **Release** garde l'exigence standard (certificat Developer ID, voir section 10).
- Vérifier : `codesign -d -r- build/DerivedData/Build/Products/Debug/LetsWork.app`.

Après un changement de signature (première application de cette exigence, passage à un certificat), réinitialiser l'autorisation puis la redemander depuis les réglages de LetsWork.

Alternative plus stricte : un certificat **Apple Development** (Xcode › Réglages › Comptes, équipe personnelle gratuite) ; renseigner alors `DEVELOPMENT_TEAM`, supprimer `CODE_SIGN_IDENTITY: "-"` et l'exigence Debug, puis `make project`.

Réinitialiser une autorisation pour retester le parcours de premier lancement :

```bash
tccutil reset Accessibility dev.projects.letswork
```

```bash
tccutil reset Calendar dev.projects.letswork
```

```bash
tccutil reset AppleEvents dev.projects.letswork
```

---

## 9. Architecture et conventions

### Arborescence

```text
LetsWork/
├── FEATURES.md                         spécification fonctionnelle
├── SETUP.md                            ce document
├── Makefile
├── project.yml                         source de vérité du projet Xcode
├── Config/                             Info.plist et entitlements (générés par XcodeGen)
├── LetsWork/
│   ├── App/
│   │   ├── LetsWorkApp.swift           point d'entrée, icône et menu de la barre de menus
│   │   ├── AppDelegate.swift           crée l'Island et la fenêtre de réglages
│   │   └── LaunchAtLogin.swift         ouverture de session (SMAppService)
│   ├── Island/
│   │   ├── ActivityCoordinator.swift   arbitrage des activités (aperçu, délai de grâce)
│   │   ├── NotchGeometry.swift         taille de l'encoche, ou encoche simulée
│   │   ├── IslandState.swift           états fermé / compact / aperçu / étendu et règle de résolution
│   │   ├── IslandMetrics.swift         dimensions par état, zone de survol
│   │   ├── IslandModel.swift           @Observable : délais de survol, épinglage, activité, onglet
│   │   ├── IslandTab.swift             onglets de l'état étendu (Accueil, Multimédia, Calendrier, Jeux)
│   │   ├── ExpandedIslandView.swift    barre d'onglets et page d'accueil
│   │   ├── IslandPanel.swift           NSPanel + vue conteneur (suivi de la souris, premier clic)
│   │   ├── IslandWindowController.swift  écran cible, clics traversants, moniteurs d'événements
│   │   ├── NotchShape.swift            forme animable de l'Island
│   │   └── IslandView.swift            forme animée et contenu de chaque état
│   ├── Settings/
│   │   ├── AppSettings.swift           clés UserDefaults, écran d'affichage
│   │   ├── SettingsView.swift          formulaire de réglages
│   │   └── SettingsWindowController.swift
│   ├── Features/
│   │   ├── Media/
│   │   │   ├── NowPlaying.swift        état de lecture, commandes, protocole NowPlayingSource
│   │   │   ├── AdapterStreamDecoder.swift  décodage du JSON de l'adaptateur
│   │   │   ├── MediaRemoteAdapterSource.swift  processus perl de l'adaptateur
│   │   │   ├── AppleScriptSource.swift repli Musique / Spotify
│   │   │   ├── MediaService.swift      @Observable : choix de la source, pochette, commandes
│   │   │   ├── MediaCompactView.swift  compact, aperçu, pochette, égaliseur
│   │   │   └── MediaExpandedView.swift lecteur étendu, progression
│   │   ├── HUD/
│   │   │   ├── HUDModel.swift          touches, pas de réglage, volume, état affiché
│   │   │   ├── MediaKeyTap.swift       event tap qui intercepte et absorbe les touches
│   │   │   ├── VolumeController.swift  volume et sourdine via Core Audio, écoute des changements
│   │   │   ├── BrightnessController.swift  luminosité de l'écran intégré principal
│   │   │   ├── HUDService.swift        @Observable : autorisation, interception, retour sonore
│   │   │   └── HUDView.swift           icône et jauge dans les ailes de l'Island
│   │   ├── Calendar/
│   │   │   ├── CalendarModel.swift     événement, liens de visio, délais, fusion, événement du compact et alertes
│   │   │   ├── EventKitProvider.swift  protocole CalendarProvider et source EventKit
│   │   │   ├── CalendarService.swift   @Observable : accès, filtres, fenêtre de 7 jours, réveils programmés
│   │   │   ├── CalendarViews.swift     compact, alerte, onglet Calendrier
│   │   │   ├── MonthCalendarView.swift mini-calendrier du mois de l'accueil
│   │   │   ├── EventDraft.swift        brouillon d'événement : valeurs par défaut, validation
│   │   │   └── EventEditor.swift       fenêtre « Nouvel événement »
│   │   ├── Notifications/
│   │   │   ├── SystemNotification.swift  notification et décodage du champ data
│   │   │   ├── NotificationDatabase.swift  lecture SQLite de la base du centre de notifications
│   │   │   ├── FileChangeWatcher.swift surveillance (kqueue) du dossier et des fichiers de la base
│   │   │   ├── NotificationService.swift  @Observable : accès, nouvelles notifications
│   │   │   └── NotificationPopupView.swift  pop-up au style de l'aperçu de piste
│   │   ├── Battery/
│   │   │   ├── BatteryStatus.swift     état de la batterie (IOKit), seuils d'alerte, textes
│   │   │   ├── BatteryService.swift    @Observable : lecture, abonnement aux changements, réglages
│   │   │   └── BatteryViews.swift      pile, niveau de l'accueil, indicateur de charge, alerte
│   │   └── Game/
│   │       ├── GamesView.swift         onglet Jeux et sélecteur Morpion / Glouton
│   │       ├── TicTacToe.swift         plateau, victoire, bot (minimax et niveaux)
│   │       ├── TicTacToeGame.swift     @Observable : tours, score, niveau, premier joueur
│   │       ├── TicTacToeView.swift     Morpion
│   │       ├── MazeGame.swift          Glouton : labyrinthe, déplacements, fantômes, vies, niveaux
│   │       ├── MazeGameController.swift  @Observable : boucle de jeu, touches, pause, record
│   │       └── MazeGameView.swift      Glouton : plateau et panneau latéral
│   └── System/
│       ├── Permissions/
│       │   └── AccessibilityPermission.swift
│       └── Private/
│           └── DisplayServices.swift   framework privé de luminosité, chargé par dlopen
├── LetsWorkTests/
│   ├── IslandTests.swift
│   ├── MediaTests.swift
│   ├── HUDTests.swift
│   ├── CalendarTests.swift
│   ├── NotificationTests.swift
│   ├── BatteryTests.swift
│   └── GameTests.swift
├── Vendor/
│   ├── mediaremote-adapter/            sous-module git (v0.7.7)
│   └── build/                          framework compilé (ignoré par git)
└── scripts/
    ├── build-mediaremote-adapter.sh    compile l'adaptateur (make adapter)
    └── embed-mediaremote-adapter.sh    phase de build qui l'embarque dans l'app
```

### Fonctionnement de l'Island (M0)

- La fenêtre (`IslandPanel`) est une zone transparente fixe de 680 × 270 pt, centrée en haut de l'écran ; la forme s'anime à l'intérieur.
- La fenêtre **ignore la souris par défaut** : les clics passent vers la barre de menus et les fenêtres situées dessous.
- Un moniteur global de mouvements de souris détecte l'entrée dans la zone de l'Island (`IslandMetrics.hitZone`). La fenêtre se met alors à capter la souris, et une zone de suivi (`NSTrackingArea`, `.activeAlways`) prend le relais tant que la souris est dessus.
- `IslandModel` applique les délais : 150 ms avant d'ouvrir, 250 ms avant de refermer. Un clic épingle l'Island ; un clic ailleurs (moniteur global) retire l'épinglage.
- La fenêtre est repositionnée quand les écrans changent et quand le réglage « Afficher sur » change.

### Flux de données

```text
Sources (adaptateur média, Core Audio, touches, EventKit…)
        │  événements
        ▼
Services de fonctionnalité (@Observable, un par feature, derrière un protocole)
        │  activités
        ▼
ActivityCoordinator (@MainActor) — applique la priorité définie dans FEATURES.md › F0
        │  état de l'Island (fermé / compact / étendu / HUD + contenu)
        ▼
IslandModel → IslandView (SwiftUI) — animations
```

- **Médias** : `MediaService.onChange` prévient `ActivityCoordinator`, qui active l'activité `.media`, déclenche l'aperçu de 3 s à chaque nouvelle piste et retire l'activité 5 s après une pause.
- **HUD** : `MediaKeyTap` (event tap de session, en tête de file) reçoit les événements système `NX_KEYTYPE_*` et les touches 144/145. `HUDService` applique le changement (Core Audio ou DisplayServices), absorbe l'événement pour que macOS n'affiche pas son indicateur, puis `HUDService.onShow` prévient `ActivityCoordinator`, qui affiche l'état `.hud` pendant 1,5 s après la dernière pression. ⌥ seul laisse passer la touche (macOS ouvre le réglage) ; ⌥⇧ règle par pas de 1/64.
- **Calendrier** : `EventKitProvider` lit les comptes macOS ; `CalendarService` fusionne et filtre les événements d'aujourd'hui à J+7, recalcule l'événement du compact et les alertes au prochain instant utile (début de la fenêtre d'une heure, alerte, début, fin), puis prévient `ActivityCoordinator` (`onUpcomingChange`, `onAlert`). Activité de fond : la lecture si elle est active, sinon la réunion. L'alerte reste 10 s, sauf clic. Rechargement sur `EKEventStoreChanged`, changement de jour et sortie de veille.
- **Notifications** : `FileChangeWatcher` (kqueue, sur le dossier, `db` et `db-wal` ; FSEvents ne remonte rien pour ce dossier protégé) signale une écriture dans la base, avec une vérification de secours toutes les 10 s ; `NotificationService` lit les enregistrements plus récents que le dernier vu, les décode et prévient `ActivityCoordinator` (`onNotification`), qui affiche l'état `.notification` 5 s et met les suivantes en file.
- **Batterie** : `BatteryService` lit la batterie interne (`IOPSCopyPowerSourcesInfo`) et s'abonne à `kIOPSNotifyAnyPowerSource` (`notify_register_dispatch`), sans interrogation périodique. `LowBatteryWatch` en déduit le branchement, le débranchement et le passage sous un seuil d'alerte ; `BatteryService.onEvent` prévient `ActivityCoordinator`, qui affiche l'indicateur de charge (`.charging`, 3 s) ou l'alerte (`.lowBattery`, 10 s, sauf clic). Le branchement retire l'alerte.
- **Clavier pendant une partie** : `IslandPanel` ne peut devenir fenêtre clé que si `acceptsKeyboardFocus` est vrai. Pendant une partie de Glouton, `IslandModel` le demande à `IslandWindowController` (`onKeyboardFocusChange`), qui rend ensuite le clavier à l'app au premier plan. Les touches passent par `IslandPanel.sendEvent` puis `IslandModel.handleKey` ; les raccourcis avec ⌘ ne sont pas interceptés.

### Conventions

- **Concurrence** : mode Swift 6 strict. Tout ce qui touche l'interface et l'état de l'Island est `@MainActor`. Les flux externes (sortie de l'adaptateur, callbacks Core Audio, event tap) sont convertis en `AsyncStream` puis consommés sur le main actor.
- **Logique pure séparée d'AppKit** (`NotchGeometry.compute`, `IslandState.resolve`, `IslandMetrics`) pour être testée sans fenêtre.
- **Une source = un protocole** (`NowPlayingSource`, `CalendarProvider`…). On peut ainsi remplacer une source cassée par une mise à jour de macOS, et tester avec des doublures.
- **API privées isolées** dans `System/Private/`, chargées par `dlopen` / `dlsym`, jamais liées. Si un symbole est absent, l'initialiseur renvoie `nil` et la fonctionnalité se désactive proprement.
- **Adaptateur média** : lancé avec `Process` (`/usr/bin/perl`, arguments : chemin absolu du `.pl` via `Bundle.main.url(forResource:withExtension:)`, chemin absolu du framework via `Bundle.main.privateFrameworksURL`, puis `stream`). Lire `stdout` ligne par ligne, décoder chaque ligne JSON, relancer le processus s'il se termine.
- **Journalisation** : `os.Logger(subsystem: "dev.projects.letswork", category: "<feature>")`.
- **Tests** : Swift Testing sur la logique pure — états de l'Island, géométrie, arbitrage des activités, dédoublonnage des événements, interpolation de la position de lecture, décodage du JSON de l'adaptateur, détection des liens de visio.
- **Secrets** : jetons OAuth uniquement dans le Trousseau ; identifiants clients OAuth hors du dépôt (fichier `.xcconfig` local ignoré par git).

---

## 10. Distribution

À traiter au jalon M4 :

1. Certificat **Developer ID Application** (compte Apple Developer payant).
2. Archive : Xcode › Product › Archive, puis « Distribute App » › Developer ID ; ou `xcodebuild archive` + `xcodebuild -exportArchive`.
3. Notarisation : `xcrun notarytool submit LetsWork.zip --keychain-profile <profil> --wait`, puis `xcrun stapler staple LetsWork.app`.
4. Paquet : DMG (ex. `create-dmg`), mises à jour automatiques avec **Sparkle**.

Tout le code embarqué (dont `MediaRemoteAdapter.framework`) doit être signé avec le hardened runtime : c'est ce que fait `codeSign: true` dans `project.yml`.

---

## 11. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `xcodegen: command not found` | Outil non installé | `brew install xcodegen` |
| `Cannot code sign because the target does not have an Info.plist` (tests) | `GENERATE_INFOPLIST_FILE` absent de la cible de tests | Vérifier la cible `LetsWorkTests` dans `project.yml` |
| Dates affichées en anglais | Langue de développement non déclarée | `developmentLanguage: fr` dans `project.yml`, puis `make project` |
| Réglages › Médias indique « Repli AppleScript » | Adaptateur non compilé ou en échec | `make adapter`, recompiler ; sinon tester l'adaptateur (section 7.1) |
| En repli, rien ne s'affiche alors que Spotify joue déjà | Autorisation Automatisation pas encore accordée : l'état n'arrive qu'avec la prochaine notification | Cliquer une fois sur un contrôle de lecture pour accorder l'autorisation, ou compiler l'adaptateur |
| Après un relancement, l'Island n'affiche plus la lecture | Une copie périmée de l'app a été ouverte (Spotlight, Finder, autre dossier de build) | `make run`, ou ⌘R dans Xcode ; vérifier le chemin avec `pgrep -lf LetsWork.app` |
| `make run` : « LetsWork tourne encore (débogueur Xcode ?) » | L'instance lancée par Xcode intercepte l'arrêt et se met en pause | Arrêter la session dans Xcode (⌘.), puis relancer `make run` |
| Les notifications n'apparaissent pas dans l'Island | Accès complet au disque absent (Réglages › Notifications l'indique), ou format de la base changé | Accorder l'accès ; sinon lire `log show --last 5m --predicate 'subsystem == "dev.projects.letswork" AND category == "notifications"'` (noms de tables et de clés uniquement) |
| Les bannières de macOS s'affichent en plus de l'Island | Mode Concentration « LetsWork » inactif | Le créer sans aucune app autorisée et l'activer depuis le Centre de contrôle |
| Plusieurs processus `mediaremote-adapter.pl` | Adaptateurs orphelins d'une instance tuée | Supprimés au prochain lancement de l'app (section 7.4) |
| En repli, les boutons de lecture n'ont aucun effet | Autorisation Automatisation refusée | Réglages Système › Confidentialité et sécurité › Automatisation |
| `cmake` échoue sur des fichiers manquants | Sous-modules de l'adaptateur absents | `git submodule update --init --recursive` |
| Test de l'adaptateur ≠ 0 | Chemins relatifs, ou macOS a de nouveau restreint MediaRemote | Utiliser des chemins absolus ; consulter les issues du projet ; s'appuyer sur le repli AppleScript |
| L'Island apparaît sous la barre de menus | Niveau de fenêtre trop bas | Vérifier `level` dans `IslandPanel` |
| L'Island disparaît en plein écran ou en changeant de Space | `collectionBehavior` incomplet | `.canJoinAllSpaces` + `.fullScreenAuxiliary` |
| Les clics sur la barre de menus près de l'encoche ne passent plus | La fenêtre capte la souris hors de l'Island | Vérifier `ignoresMouseEvents` dans `IslandWindowController.handleMouse` |
| L'autorisation Accessibilité est perdue à chaque build | Signature ad hoc | Signer avec un certificat Apple Development (section 8) |
| Les indicateurs de macOS s'affichent toujours | Autorisation Accessibilité absente, ou accordée à une signature différente (journal `tccd` : « Failed to match existing code requirement ») | Réglages › Volume et luminosité doit indiquer « Interception : Active ». Sinon : `tccutil reset Accessibility dev.projects.letswork`, puis « Autoriser… » (section 8) |
| Une touche d'un clavier externe affiche encore l'indicateur de macOS | La touche arrive sous une forme non reconnue (ex. un utilitaire de clavier la réémet) | Activer le diagnostic : `defaults write dev.projects.letswork hudDiagnostics -bool true`, appuyer sur la touche, puis lire `log show --last 2m --predicate 'subsystem == "dev.projects.letswork"'` (code, modificateurs, processus source, absorbée ou transmise). Le désactiver ensuite avec `defaults delete dev.projects.letswork hudDiagnostics`. Seules les touches spéciales et de fonction sont journalisées, jamais la frappe |
| L'onglet Calendrier est vide ou un compte manque | Accès non accordé, calendrier masqué, ou compte absent de macOS | Réglages › Calendrier : accès « Accordé » et calendrier coché ; ajouter le compte dans Réglages Système › Comptes internet (Google, Exchange) |
| Les touches de luminosité ne passent pas par LetsWork | L'écran principal est externe, ou DisplayServices est indisponible | Comportement voulu : macOS garde la main (FEATURES.md, F2) |
| L'app apparaît dans le Dock | `LSUIElement` absent | Vérifier `info.properties` dans `project.yml`, puis `make project` |
