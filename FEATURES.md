# LetsWork — Spécification fonctionnelle

> Application macOS qui transpose le principe du **Dynamic Island** à l'encoche (notch) des MacBook Pro :
> une surface animée, affichée par-dessus l'écran, qui présente l'activité en cours du Mac
> (médias, volume, luminosité, agenda) et permet d'agir dessus sans quitter son application.

Ce document décrit **ce que fait** l'application. La mise en place technique du projet est décrite dans [SETUP.md](SETUP.md).

---

## Sommaire

- [Glossaire](#glossaire)
- [F0 — Socle : l'Island](#f0--socle--lisland)
- [F1 — Gestion des médias](#f1--gestion-des-médias)
- [F2 — HUD volume et luminosité](#f2--hud-volume-et-luminosité)
- [F3 — Calendrier multi-sources](#f3--calendrier-multi-sources)
- [F4 — Notifications des apps](#f4--notifications-des-apps)
- [F5 — Jeux : Morpion et Glouton](#f5--jeux--morpion-et-glouton)
- [F6 — Batterie](#f6--batterie)
- [Exigences non fonctionnelles](#exigences-non-fonctionnelles)
- [Jalons](#jalons)
- [Questions ouvertes](#questions-ouvertes)

---

## Glossaire

| Terme | Définition |
|---|---|
| **Island** | La forme noire animée, ancrée au centre du bord supérieur de l'écran, qui prolonge visuellement l'encoche. |
| **État fermé** | L'Island épouse exactement l'encoche : invisible pour l'utilisateur. |
| **État compact** | L'Island s'élargit de part et d'autre de l'encoche (« ailes ») pour afficher une information courte : pochette + égaliseur, prochain rendez-vous, etc. |
| **État étendu** | L'Island se déploie vers le bas en panneau complet avec contrôles. Déclenché au survol ou au clic. |
| **État HUD** | Affichage temporaire (≈ 1,5 s) d'un indicateur système : volume, luminosité. |
| **Activité** | Toute information qu'une fonctionnalité veut afficher dans l'Island (lecture en cours, changement de volume, réunion imminente). |
| **Source** | Origine d'une activité média (Spotify, Apple Music, Safari, Chrome…) ou d'un agenda (iCloud, Google, Outlook). |

---

## F0 — Socle : l'Island

Les trois fonctionnalités s'appuient sur un socle commun, à construire en premier.

### Comportement attendu

- **Fenêtre de premier plan** : l'Island est une fenêtre sans bordure, transparente, non activante (elle ne vole jamais le focus à l'application courante), affichée au-dessus de la barre de menus, sur **tous les Spaces** et **par-dessus les applications en plein écran**.
- **Ancrage sur l'encoche** : sur un écran avec encoche, l'état fermé reprend exactement la largeur et la hauteur de l'encoche (calculées à partir de `NSScreen.safeAreaInsets` et `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`).
- **Écrans sans encoche** (écran externe, Mac sans notch) : l'Island est simulée par une pilule noire centrée en haut de l'écran, masquée à l'état fermé (option : toujours visible).
- **Transitions** : fermé ↔ compact ↔ étendu ↔ HUD par animations à ressort (spring), la forme se déformant de manière continue (pas d'apparition/disparition sèche).
- **Interactions** :
  - survol → passage en étendu après un court délai (≈ 150 ms) ; sortie du survol → retour à l'état précédent ;
  - clic → étendu « épinglé » jusqu'au prochain clic extérieur ;
  - onglets de l'état étendu, en haut à gauche à côté de l'encoche : **Accueil** (date, heure, puis « En lecture : Titre — Artiste » ou « En pause : … » quand un média est en cours — un clic ouvre l'onglet Multimédia — sinon « Aucune activité pour le moment » ; à droite, un mini-calendrier du mois à la manière du widget Calendrier de macOS, qui ouvre l'onglet Calendrier) **Multimédia** (lecteur, ou « Aucune lecture en cours »), **Calendrier** (F3) et **Jeux** (F5 : Morpion, Glouton) ; le calendrier (F3) y ajoutera son onglet. L'onglet choisi est conservé d'une ouverture à l'autre, en commençant par Accueil ;
  - swipe horizontal à deux doigts sur l'Island → bascule entre les activités (média ↔ agenda).
- **Clics traversants** : les zones transparentes de la fenêtre ne doivent jamais bloquer les clics sur la barre de menus ou les fenêtres situées dessous.
- **Multi-écrans** : réglage « Afficher sur » : écran avec encoche (défaut) / écran principal / écran sous la souris / tous les écrans.
- **Masquage automatique** : l'Island se masque pendant les partages d'écran et quand une application plein écran le demande (option, ex. jeux, Keynote).

### Arbitrage des activités

Plusieurs fonctionnalités peuvent vouloir s'afficher en même temps. Un **coordinateur d'activités** décide de ce qui est montré, selon cette priorité :

1. **HUD** (volume / luminosité) — interrompt tout, temporaire ;
2. **Survol ou épinglage** — état étendu ;
3. **Batterie faible** (F6) — temporaire ;
4. **Alerte calendrier** (réunion dans ≤ 5 min / en cours) — temporaire, puis retour à l'activité de fond ;
5. **Notification** d'une autre app (F4) — temporaire, les suivantes en file ;
6. **Indicateur de charge** au branchement (F6) — ≈ 3 s ;
7. **Changement de piste** — compact pendant ≈ 3 s ;
8. **Activité de fond** : lecture média en cours, sinon prochain événement (un événement commencé : 10 s seulement), sinon état fermé.

### Application et réglages

- Application « agent » : **pas d'icône dans le Dock**, une icône dans la barre de menus (réglages, pause, quitter).
- **Lancement à l'ouverture de session** (activable dans les réglages).
- Fenêtre de réglages : activation/désactivation de chaque fonctionnalité, écran cible, comportement au survol, apparence.
- **Assistant de premier lancement** : explique et demande une à une les autorisations nécessaires (voir chaque fonctionnalité), avec un état visible (accordée / refusée / à faire) et un bouton vers les Réglages Système.

### Critères d'acceptation

- [ ] L'Island fermée est indiscernable de l'encoche sur un MacBook Pro 14"/16".
- [ ] L'Island reste visible au-dessus d'une application en plein écran et en changeant de Space.
- [ ] L'application au premier plan conserve le focus clavier quand on survole ou clique l'Island.
- [ ] Un clic sur un menu de la barre de menus, à côté de l'Island, fonctionne normalement.
- [ ] Débrancher/brancher un écran externe repositionne l'Island sans redémarrage.

---

## F1 — Gestion des médias

### Objectif

Voir et piloter **ce qui joue sur le Mac**, quelle que soit la source : application musicale (Apple Music, Spotify) ou **vidéo dans un navigateur** (YouTube dans Safari, Chrome, Arc, Firefox…).

### User stories

- En tant qu'utilisateur, je vois en un coup d'œil le titre en cours et la source, sans changer de fenêtre.
- Je peux mettre en pause, reprendre, passer au titre suivant/précédent et me déplacer dans la piste depuis l'Island.
- Quand une vidéo YouTube joue dans mon navigateur, l'Island l'indique avec l'icône du navigateur.
- Un clic sur la pochette ou l'icône de la source ramène l'application (ou le navigateur) au premier plan.
- Quand Spotify joue, je peux activer l'aléatoire ou la répétition, et liker le titre en cours, sans ouvrir Spotify.

### Affichage

| État | Contenu |
|---|---|
| **Compact** | Aile gauche : pochette miniature (ou icône de la source). Aile droite : égaliseur animé si lecture en cours, icône pause sinon. |
| **Étendu** (onglet Multimédia) | Pochette grand format, titre, artiste/chaîne, album, icône de la source, barre de progression interactive (temps écoulé / durée), boutons précédent / lecture-pause / suivant. Avec Spotify : cœur « J'aime » à gauche de l'icône de la source, boutons aléatoire et répétition de part et d'autre des contrôles (teinte de la pochette et point dessous quand le mode est actif). Teinte d'accent dérivée de la couleur dominante de la pochette. Sur la partie écoulée de la barre, trois couches de dômes animées défilent en sens opposés, chacune dans une nuance de la pochette (discrète, intermédiaire, contrastée) ; elles s'aplatissent et se figent en pause, et restent immobiles si « Réduire les animations » est activé. |
| **Changement de piste** | Passage en compact enrichi (titre défilant) pendant ≈ 3 s. |

### Sources et méthodes de récupération

| Source | Méthode principale | Informations | Contrôles |
|---|---|---|---|
| Toute app publiant dans le « Now Playing » de macOS (Apple Music, Spotify, Podcasts, TV, navigateurs, VLC, IINA…) | **MediaRemote** (framework privé) via [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) | titre, artiste, album, durée, position, pochette, état lecture, bundle id de l'app source | lecture, pause, bascule, suivant, précédent, seek |
| Safari, Chrome, Edge, Arc, Brave, Firefox | Même canal : les navigateurs exposent la Media Session API des pages (YouTube, Netflix, SoundCloud…) au Now Playing de macOS | titre de la vidéo, chaîne, durée, position, vignette (selon le site) | idem (selon ce que la page déclare) |
| Spotify, Apple Music (complément) | **AppleScript / Scripting Bridge** + notifications distribuées `com.spotify.client.PlaybackStateChanged` et `com.apple.Music.playerInfo` | état de **chaque** app, même quand elle n'est pas la source « active » | lecture, pause, suivant, précédent, position |
| Spotify (commandes propres) | **AppleScript** de Spotify, plus l'**API Web Spotify** pour la bibliothèque | aléatoire, répétition, URI du titre (`spotify:track:…`) ; titre liké ou non | aléatoire, répétition, « J'aime » |

**Pourquoi un adaptateur ?** Depuis macOS 15.4, le framework MediaRemote n'est plus utilisable directement depuis une application tierce. `mediaremote-adapter` contourne la restriction en faisant exécuter un petit framework par `/usr/bin/perl`, binaire système autorisé, et diffuse les changements en JSON sur la sortie standard (`stream`). Les commandes passent par `send <id>` et `seek <µs>`. Le canal reste **non officiel** : il peut casser à chaque mise à jour de macOS ; il doit donc être isolé derrière une interface, avec le canal AppleScript comme repli.

### Règles de gestion

- **Source affichée** : celle que macOS considère comme « Now Playing ». Si plusieurs apps sont en pause, la dernière active reste affichée en état étendu ; en compact, rien n'est affiché tant que rien ne joue (option : garder la dernière source visible).
- **Identification de la source** : icône et nom résolus depuis le bundle id (`NSWorkspace.urlForApplication(withBundleIdentifier:)`). Pour un navigateur, afficher l'icône du navigateur ; si le titre de la page/le domaine est disponible, l'afficher en sous-titre.
- **Position de lecture** : interpolée localement entre deux mises à jour (position + vitesse + horodatage) pour une barre de progression fluide, sans interroger la source en continu.
- **Pochette absente** : icône de l'application source sur fond flouté.
- **Fin de lecture / fermeture de l'app source** : retour à l'activité suivante selon l'arbitrage F0 après ≈ 5 s.

### Spotify : aléatoire, répétition et « J'aime »

Spotify ne publie dans le « Now Playing » de macOS ni son mode aléatoire, ni sa répétition, ni l'identifiant du titre : ces commandes passent par l'AppleScript de Spotify (`shuffling`, `repeating`, `id of current track`), quelle que soit la source de lecture (adaptateur ou repli).

- **Visibilité** : les trois boutons n'apparaissent que si la lecture en cours vient de Spotify.
- **État** : relu par AppleScript 0,3 s après chaque changement de titre et à chaque ouverture de l'onglet Multimédia (pour suivre ce qui a été changé dans Spotify), puis 0,5 s après un clic pour afficher l'état réellement appliqué. Cette lecture ne déclenche jamais la demande d'autorisation : c'est le premier clic sur un des boutons qui la déclenche.
- **Répétition** : l'AppleScript de Spotify ne connaît que « activée / désactivée » ; l'activer répète la playlist ou l'album. La répétition du titre seul reste à choisir dans Spotify.
- **« J'aime »** : l'API Web Spotify (`GET /me/library/contains`, `PUT` et `DELETE /me/library`, avec l'URI du titre). Le cœur est plein si le titre est dans « Titres likés ». Il change dès le clic et revient en arrière si Spotify refuse. Les épisodes de podcast s'enregistrent de la même façon ; publicités et fichiers locaux ne se likent pas.
- **Compte Spotify** : connexion dans Réglages › Spotify, par le flux OAuth *Authorization Code with PKCE* (aucun secret dans l'app). Il faut une app créée sur developer.spotify.com, son Client ID et l'URI de redirection `http://127.0.0.1:43219/callback`, écoutée par LetsWork le temps de la connexion (5 min au plus). Le jeton de rafraîchissement va dans le Trousseau ; le jeton d'accès reste en mémoire et se renouvelle de lui-même. Depuis février 2026, une app Spotify en mode développement exige que son propriétaire soit abonné à Premium.
- **Sans compte connecté** : un clic sur le cœur ouvre les réglages.
- **Erreurs** : le dernier refus de Spotify s'affiche dans Réglages › Spotify. Un jeton révoqué ou expiré déconnecte le compte.

### Autorisations

- **Automatisation** (Apple Events) vers Spotify et Music, demandée si le canal AppleScript est utilisé, et vers Spotify au premier clic sur l'aléatoire, la répétition ou « J'aime ».
- Aucune autorisation n'est nécessaire pour le canal MediaRemote via l'adaptateur.
- **Compte Spotify** (OAuth, scopes `user-library-read` et `user-library-modify`), seulement pour « J'aime ».

### Critères d'acceptation

- [ ] Lecture dans Apple Music : titre, artiste, pochette et progression s'affichent en < 1 s après le démarrage.
- [ ] Lecture dans Spotify : idem, et les contrôles agissent sur Spotify.
- [ ] Spotify : les boutons aléatoire et répétition reflètent l'état de Spotify et le changent ; le cœur indique si le titre est liké, et un clic l'ajoute aux « Titres likés » ou l'en retire.
- [ ] Vidéo YouTube dans Safari puis dans Chrome : l'Island affiche le titre de la vidéo et l'icône du bon navigateur ; pause/lecture fonctionne depuis l'Island.
- [ ] Le seek dans la barre de progression déplace réellement la lecture.
- [ ] Si l'adaptateur échoue (`test` ≠ 0), l'app bascule sur le canal AppleScript pour Music/Spotify et le signale dans les réglages.
- [ ] CPU de l'app < 1 % en moyenne pendant une lecture (hors animation d'égaliseur).

### Limites connues (M1)

- **Repli AppleScript** : sans autorisation Automatisation déjà accordée, l'état de Spotify ou de Musique n'est connu qu'à leur prochaine notification (lecture, pause, changement de piste) ; pas de pochette ; vidéos des navigateurs non détectées.
- **Aperçu de changement de piste** : le titre est tronqué, pas encore défilant.
- **Égaliseur** : animation décorative, sans lien avec le signal audio (voir évolutions).

### Évolutions (hors v1)

- Visualiseur audio réel (spectre) via les *process taps* Core Audio (macOS 14.2+) — nécessite l'autorisation d'enregistrement audio.
- Ajout à une playlist (API Web Spotify) ; « J'aime », aléatoire et répétition pour Apple Music (AppleScript).
- Sélecteur de sortie audio (AirPods, enceintes AirPlay).

---

## F2 — HUD volume et luminosité

### Objectif

Remplacer les indicateurs natifs de macOS (volume, luminosité de l'écran, et en option rétroéclairage du clavier) par des **animations dans l'Island**, cohérentes avec le reste de l'application.

### User stories

- Quand j'appuie sur une touche de volume, l'indicateur natif de macOS n'apparaît pas : l'Island s'étire et affiche une jauge animée.
- Quand j'appuie sur une touche de luminosité, même comportement avec une jauge de luminosité.
- Si je coupe le son, l'Island l'indique clairement (icône barrée, jauge vide).
- Si je quitte LetsWork, les touches retrouvent leur comportement natif.

### Affichage

- **État HUD** : ailes de l'Island étirées ; à gauche l'icône (haut-parleur avec niveau, soleil, clavier), à droite une jauge horizontale + pourcentage optionnel.
- La jauge s'anime à chaque pression (ressort léger), l'icône change selon le palier (muet / bas / moyen / fort).
- Disparition automatique après ≈ 1,5 s sans nouvelle pression ; chaque pression relance le délai.
- Si le périphérique de sortie ne permet pas le réglage du volume (HDMI, certaines cartes son) : icône « non disponible », comme macOS.
- Optionnel : nom du périphérique de sortie (« Haut-parleurs MacBook Pro », « AirPods Pro ») sous la jauge.

### Fonctionnement

1. **Interception des touches** — un *event tap* (`CGEvent.tapCreate`, au niveau session, en tête de file) capte les événements système des touches spéciales (`NSEvent` de type `systemDefined`, sous-type 8) : `NX_KEYTYPE_SOUND_UP/DOWN`, `NX_KEYTYPE_MUTE`, `NX_KEYTYPE_BRIGHTNESS_UP/DOWN`, `NX_KEYTYPE_ILLUMINATION_UP/DOWN`.
2. **Consommation** — l'événement est absorbé (le callback renvoie `nil`) : macOS ne l'applique pas et n'affiche donc pas son HUD.
3. **Application** — LetsWork applique lui-même le changement :
   - **volume** : Core Audio sur le périphérique de sortie par défaut (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, `kAudioDevicePropertyMute`) ;
   - **luminosité de l'écran intégré** : framework privé `DisplayServices` (`DisplayServicesGetBrightness` / `DisplayServicesSetBrightness`) chargé dynamiquement ;
   - **rétroéclairage clavier** (option) : framework privé `CoreBrightness` (`KeyboardBrightnessClient`).
4. **Affichage** — le coordinateur d'activités passe l'Island en état HUD.
5. **Changements externes** — un écouteur Core Audio (`AudioObjectAddPropertyListenerBlock`) détecte les changements faits ailleurs (Centre de contrôle, AirPods, autre app) et met l'Island à jour (affichage HUD optionnel dans ce cas).

### Règles de gestion

- **Pas** de volume : 1/16 par pression (comme macOS). **⌥ + ⇧ + touche** : pas fin de 1/64 (comme macOS).
- **⌥ + touche** : ouvrir le panneau Son / Moniteurs des Réglages Système (comportement natif conservé).
- **Muet** : bascule ; une pression sur « volume + » quand le son est coupé le rétablit.
- **Retour sonore** : jouer le « pop » système au changement de volume si l'utilisateur l'a activé dans macOS.
- **Robustesse** : si macOS désactive l'event tap (timeout ou entrée utilisateur), le réactiver immédiatement (`tapDisabledByTimeout`). Si l'autorisation Accessibilité est retirée, ne rien intercepter : le HUD natif reprend la main.
- **Écrans externes** : hors v1 (DDC/CI). Si l'écran principal est externe, ne pas intercepter les touches de luminosité.

### Points à valider en début de développement (spike)

- Sur les MacBook Pro Apple Silicon, vérifier sous quelle forme arrivent les touches de luminosité : événement `systemDefined` (`NX_KEYTYPE_BRIGHTNESS_*`) ou `keyDown` avec les keyCodes 144/145 selon le réglage « Utiliser F1, F2… comme touches de fonction standard ». **Constaté pendant M2** : le clavier intégré envoie des événements `systemDefined` ; un Logitech MX Keys S, via l'agent Logi Options+, réémet ses touches F1/F2 en **F14/F15** (codes 107/113), que macOS associe par défaut à la luminosité. M2 gère ces trois formes (événement système, 144/145, F14/F15).
- Vérifier sur la version de macOS cible que l'absorption de l'événement suffit à masquer le HUD natif. L'ancienne technique consistant à tuer le processus `OSDUIHelper` ne fonctionne plus depuis macOS 26 (le processus n'existe plus) et ne doit pas être utilisée.
- Vérifié pendant M2 (macOS 27.0.1) : les fonctions `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness` et `DisplayServicesCanChangeBrightness` sont présentes et lisent bien la luminosité de l'écran intégré.

### Limites connues (M2)

- **Rétroéclairage du clavier** : non géré ; les MacBook Pro Apple Silicon n'ont pas de touches dédiées.
- **F14/F15** : toujours traitées comme luminosité −/+ (raccourcis par défaut de macOS). Si ces touches ont été réaffectées à autre chose, LetsWork les intercepte quand même.
- **Changements externes** : seuls les changements de volume (Centre de contrôle, AirPods, autre app) affichent le HUD, et uniquement quand l'interception est active. Les changements de luminosité externes (capteur de lumière ambiante, Centre de contrôle) ne l'affichent pas, pour ne pas le déclencher en continu.
- **Nom de la sortie audio** : pas encore affiché sous la jauge.
- **Priorité** : le HUD remplace aussi l'Island étendue pendant 1,5 s, conformément à l'arbitrage F0.

### Autorisations

- **Accessibilité** (obligatoire pour un event tap qui modifie/absorbe les événements). Vérification via `AXIsProcessTrustedWithOptions`, avec invite et lien vers Réglages Système › Confidentialité et sécurité › Accessibilité.

### Critères d'acceptation

- [ ] Touches volume +/−/muet : aucun HUD natif, HUD LetsWork animé, niveau réel modifié et cohérent avec le Centre de contrôle.
- [ ] Touches luminosité +/− sur l'écran intégré : aucun HUD natif, luminosité réellement modifiée.
- [ ] Changer le volume depuis le Centre de contrôle met à jour la valeur affichée par LetsWork.
- [ ] Quitter LetsWork (ou retirer l'autorisation Accessibilité) restaure le comportement natif sans redémarrage.
- [ ] Appuis rapides répétés : aucune latence perceptible (< 16 ms entre l'appui et la mise à jour de la jauge).

---

## F3 — Calendrier multi-sources

### Objectif

Afficher l'agenda de l'utilisateur dans l'Island en **agrégeant plusieurs comptes** (Outlook / Microsoft 365, Google / Gmail, iCloud…), et le prévenir de ses prochaines réunions.

### User stories

- Je vois mon prochain rendez-vous et le temps restant avant qu'il commence.
- En étendu, je vois les événements de la journée, toutes sources confondues, avec la couleur de chaque calendrier.
- Quelques minutes avant une réunion en ligne, l'Island me prévient et propose un bouton « Rejoindre » (Teams, Meet, Zoom, Webex).
- Je choisis quels calendriers sont affichés.
- J'ajoute un événement dans le calendrier de mon choix, regroupé par compte (iCloud, Google, Exchange…).

### Affichage

| État | Contenu |
|---|---|
| **Compact** (activité de fond, si aucun média ne joue) | Pastille de couleur du calendrier + titre court + « dans 12 min » / « en cours ». Un événement commencé ne reste en compact que 10 s, puis seulement sur l'accueil. |
| **Alerte** (T − 5 min, configurable) | Compact enrichi avec titre, heure, bouton « Rejoindre » si un lien de visio est détecté. Disparaît après ≈ 10 s ou au clic. |
| **Étendu** | Liste chronologique de la journée (événements passés grisés), événements « toute la journée » en tête, sélecteur de jour (aujourd'hui / demain), indicateur de l'heure courante. |

### Sources et méthodes

| Source | Méthode | Remarques |
|---|---|---|
| Comptes ajoutés à macOS (iCloud, **Google**, **Exchange / Outlook**, CalDAV) | **EventKit** (`EKEventStore`) | Une seule API pour tous les comptes déjà configurés dans Réglages Système › Comptes internet ou dans l'app Calendrier. **Voie prioritaire v1.** |
| Google Calendar (compte non ajouté à macOS) | **Google Calendar API** (REST), OAuth 2.0 + PKCE | Synchronisation incrémentale (`syncToken`), scope lecture seule `calendar.readonly`. |
| Outlook / Microsoft 365 (compte non ajouté à macOS, ex. tenant d'entreprise bloquant Exchange) | **Microsoft Graph** (`/me/calendarView`), OAuth 2.0 + PKCE | Scope `Calendars.Read`, requêtes delta pour la synchro. Peut nécessiter le consentement d'un administrateur du tenant. |

Toutes les sources implémentent une même interface `CalendarProvider` ; un agrégateur fusionne les résultats.

### Règles de gestion

- **Fenêtre de données** : aujourd'hui + 7 jours, rafraîchie à chaque changement (`EKEventStoreChanged` pour EventKit) et périodiquement (≈ 5 min) pour les API distantes.
- **Dédoublonnage** : un même événement présent dans deux sources (ex. invitation Outlook transférée vers Google) n'est affiché qu'une fois — clé : titre normalisé + début + fin (+ iCalUID quand disponible).
- **Événements ignorés** : refusés par l'utilisateur, annulés ; option pour masquer les « toute la journée ».
- **Détection de visio** : recherche de liens Teams (`teams.microsoft.com`), Meet (`meet.google.com`), Zoom (`*.zoom.us/j/`), Webex dans l'URL, le lieu et les notes de l'événement ; « Rejoindre » ouvre le lien (ou l'app native si installée).
- **Fuseaux horaires** : tout est affiché dans le fuseau du Mac.
- **Hors ligne** : les dernières données synchronisées restent affichées, avec un indicateur discret.
- **Sécurité** : jetons OAuth stockés dans le **Trousseau** (Keychain) ; aucune donnée d'agenda envoyée ailleurs que chez le fournisseur concerné ; cache local chiffré ou limité au strict nécessaire.

### Autorisations

- **Calendriers — accès complet** (`requestFullAccessToEvents`, macOS 14+) pour EventKit.
- **Connexion OAuth** dans une session d'authentification système (`ASWebAuthenticationSession`) pour Google et Microsoft ; enregistrement préalable d'une application cliente chez Google Cloud et Microsoft Entra ID.

### Critères d'acceptation

- [ ] Avec un compte Google et un compte Exchange ajoutés à macOS, les événements des deux apparaissent, aux bonnes couleurs, sans configuration supplémentaire.
- [ ] Un événement créé dans l'app Calendrier apparaît dans l'Island en < 5 s.
- [ ] Une réunion Teams/Meet/Zoom déclenche l'alerte à T − 5 min avec un bouton « Rejoindre » fonctionnel.
- [ ] Un événement en double dans deux sources n'apparaît qu'une fois.
- [ ] Refuser l'accès aux calendriers désactive proprement la fonctionnalité (message + lien vers les réglages), sans plantage.

### Création d'événements

- **Ouverture** : bouton **+** de l'onglet Calendrier (sur le jour affiché), ou menu de la barre des menus › « Nouvel événement… » (⌘N).
- **Fenêtre dédiée** « Nouvel événement », sous l'Island : le panneau de l'Island ne prend pas le clavier et se referme quand la souris s'éloigne.
- **Champs** : titre, calendrier (seuls les calendriers modifiables, regroupés par compte), toute la journée, début et fin, lieu, lien de visio, notes.
- **Valeurs par défaut** : aujourd'hui, la prochaine demi-heure ; un autre jour, 9:00 ; durée d'une heure, conservée quand on déplace le début ; dernier calendrier utilisé, sinon celui proposé par macOS.
- **Validation** : titre, calendrier, fin après le début, lien en http(s) ; le message s'affiche en bas de la fenêtre.
- **Enregistrement** via EventKit ; macOS synchronise ensuite l'événement avec le compte. Un lien de visio saisi active le bouton « Rejoindre ».

### Décisions et limites (M3)

- **Sources** : EventKit seul pour l'instant, derrière l'interface `CalendarProvider`. Les fournisseurs Google Calendar et Microsoft Graph demandent d'enregistrer une application cliente OAuth chez Google Cloud et Microsoft Entra ID ; ils restent à faire (voir Questions ouvertes).
- **Compact** : l'événement apparaît une heure avant son début ; une fois commencé, il reste 10 s puis se masque (10 s après son apparition s'il était déjà en cours, par exemple au lancement de LetsWork) et ne reste affiché que sur l'accueil (« En cours : Titre ») et dans l'onglet Calendrier. Une mise à jour de l'agenda ne le réaffiche pas ; l'événement suivant réapparaît normalement. La lecture d'un média reste prioritaire. Les événements sur la journée entière n'apparaissent pas en compact.
- **Alerte** : une seule fois par événement et par lancement de l'app ; délai réglable (1, 5, 10 ou 15 min, 5 par défaut).
- **Accueil** : ligne « En cours : Titre » ou « Prochain : Titre · dans 12 min », et mini-calendrier du mois (mois en rouge, semaine commençant le lundi, week-ends grisés, jour actuel dans une pastille rouge) ; les deux ouvrent l'onglet Calendrier.
- **Accès** : demandé depuis l'onglet Calendrier ou les réglages, jamais au lancement.
- **« Rejoindre »** : ouvre le lien https ; l'app de visio le prend en charge si elle est installée.
- **Calendriers affichés** et **journées entières masquées** : réglables dans Réglages › Calendrier.

### Évolutions (hors v1)

- Rappels (`EKReminder`) ; modification et suppression d'événements depuis l'Island ; invités et alertes personnalisées à la création.
- Statut « occupé » : passer le Mac en mode Concentration pendant les réunions.

---

## F4 — Notifications des apps

### Objectif

Afficher les notifications des autres apps (Messages, Slack, Mail…) dans une pop-up de l'Island, au style de l'aperçu d'un titre musical, **à la place** des bannières de macOS.

### Fonctionnement

- **Lecture** : macOS n'offre aucune API pour lire les notifications des autres apps. LetsWork lit la base du centre de notifications (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`, SQLite, tables `app` et `record`, champ `data` en plist avec `req` › `titl`, `subt`, `body`). Cette base est protégée : LetsWork a besoin de l'**accès complet au disque**.
- **Détection** : surveillance directe (kqueue) du dossier de la base et des fichiers `db` et `db-wal`, puis lecture des enregistrements plus récents que le dernier vu ; vérification de secours toutes les 10 s. FSEvents ne remonte rien pour ce dossier protégé. Seules les notifications reçues après le lancement de LetsWork sont affichées.
- **Remplacement des bannières** : aucune API ne permet de masquer les bannières de macOS. L'utilisateur crée un mode Concentration « LetsWork » qui n'autorise aucune app et l'active ; les notifications restent dans le centre de notifications, et LetsWork les affiche.

### Affichage

| Élément | Contenu |
|---|---|
| Ailes | Icône de l'app à gauche, nom de l'app à droite. |
| Sous l'encoche | Titre en gras (sinon sous-titre, sinon nom de l'app) ; dessous, sous-titre et texte, tronqués. |
| Durée | 5 s ; les notifications suivantes attendent leur tour. |
| Clic | Ouvre l'app d'origine (macOS ne permet pas d'ouvrir la notification elle-même) et passe à la suivante. |
| Priorité | Après le HUD, le survol et l'alerte de réunion ; avant l'aperçu de piste et le compact. |

### Confidentialité

- Lecture locale uniquement : rien n'est enregistré ni envoyé.
- Le journal ne contient jamais le contenu des notifications, seulement les noms de tables, de colonnes et de clés en cas de format inattendu.
- L'accès complet au disque donne à LetsWork l'accès à tous les fichiers de l'utilisateur ; il est demandé uniquement pour cette fonctionnalité, désactivable dans les réglages.

### Limites connues

- **Délai d'environ 5 s** : macOS n'écrit la notification dans sa base qu'environ 5 s après l'envoi (mesuré sur macOS 27.0.1, toutes tables comprises) ; LetsWork l'affiche dès cette écriture. Le tri intelligent du mode Concentration peut y contribuer.
- **Format privé** : la base et son format peuvent changer à chaque mise à jour de macOS ; Apple l'a déjà déplacée et protégée dans macOS 15. Structure constatée sur macOS 27.0.1 : identique à celle attendue (`app`, `record` › `data` › `req`).
- **Mode Concentration requis** pour masquer les bannières ; sans lui, LetsWork affiche les notifications en plus des bannières.
- **Pas d'actions** : impossible de répondre ou d'utiliser les boutons d'une notification depuis LetsWork.
- Une notification arrivée pendant que l'Island est survolée peut passer inaperçue.

### Critères d'acceptation

- [ ] Avec l'accès complet au disque, une notification de Messages ou Slack s'affiche dans l'Island dès que macOS l'a enregistrée (environ 5 s).
- [ ] Avec le mode Concentration « LetsWork » actif, aucune bannière de macOS n'apparaît.
- [ ] Plusieurs notifications rapprochées s'affichent l'une après l'autre.
- [ ] Un clic ouvre l'app d'origine.
- [ ] Sans l'accès complet au disque, les réglages l'indiquent et LetsWork démarre la lecture dès qu'il est accordé.

---

## F5 — Jeux : Morpion et Glouton

### Objectif

Un onglet **Jeux** dans l'Island étendue, avec un sélecteur **Morpion / Glouton** dans l'espace à droite de l'encoche. Chaque partie est conservée quand l'Island se referme.

### Morpion

- L'utilisateur joue les **X** (cyan), le bot les **O** (rose).
- **Niveaux** : Facile (coups au hasard), Moyen (meilleur coup 7 fois sur 10), Imbattable (minimax : ne perd jamais). Le niveau est mémorisé.
- **Premier joueur** : il alterne à chaque « Nouvelle partie ».
- Le bot joue après un court temps de réflexion (0,45 s) ; on ne peut pas jouer pendant son tour.
- La ligne gagnante est mise en évidence ; le score Vous / Bot / Nuls vaut pour la session.
- La partie est conservée quand l'Island se referme.

### Glouton

Jeu de labyrinthe dans l'esprit de Pac-Man (marque de Bandai Namco), avec un labyrinthe, des formes et des couleurs propres à LetsWork.

- **Labyrinthe** de 19 × 11 cases, avec un tunnel sur la ligne du milieu ; pastilles (10 points) et super-pastilles (50 points).
- **Fantômes** : un poursuivant (vise le glouton), un embusqué (vise quatre cases devant lui), un errant ; plus lents au début, ils accélèrent à partir du niveau 3.
- **Super-pastille** : les fantômes ont peur pendant 40 pas (ils clignotent à la fin) ; en manger un rapporte 200, puis 400, 800…
- **3 vies** ; toutes les pastilles mangées : niveau suivant. Record mémorisé.
- **Clavier** : flèches pour diriger, Espace pour la pause, Échap pour quitter, Entrée pour rejouer.
- **Clavier et Island** : l'Island ne prend le clavier que pendant une partie (de « Jouer » jusqu'à Échap, un clic à côté ou un autre onglet), puis le rend à l'app au premier plan. Pendant la partie, l'Island reste ouverte même si la souris s'éloigne. Le jeu se met en pause dès que l'onglet n'est plus affiché.

### Critères d'acceptation

- [ ] Un clic sur une case vide y place un X, puis le bot répond.
- [ ] Au niveau Imbattable, le joueur ne gagne jamais (vérifié par un test sur toutes les parties possibles).
- [ ] « Nouvelle partie » vide le plateau et alterne le premier joueur.
- [ ] Glouton : les flèches dirigent le glouton ; après Échap, la frappe revient à l'app au premier plan.
- [ ] Glouton : la boucle de jeu s'arrête quand l'onglet n'est plus affiché.

---

## F6 — Batterie

### Objectif

Voir le niveau de la batterie dans l'Island, être averti du branchement du chargeur à la manière de l'iPhone, et être prévenu quand il faut brancher le Mac.

### Affichage

| Élément | Contenu |
|---|---|
| **Accueil** (état étendu) | Dans l'espace à droite de l'encoche : pourcentage et pile remplie au niveau exact, verte sur secteur (avec un éclair en charge), rouge à 20 % ou moins sur batterie, blanche sinon. |
| **Branchement du chargeur** | Pendant ≈ 3 s, dans les ailes : éclair vert et « En charge » (ou « Chargée », « Sur secteur » quand macOS suspend la charge) à gauche ; pourcentage et pile à droite. |
| **Batterie faible** | Pile et pourcentage en rouge dans les ailes ; sous l'encoche, « Batterie faible » puis « Branchez votre Mac sur le secteur · environ 25 min restantes » (autonomie estimée par macOS, si elle est connue). Disparaît après ≈ 10 s, au clic ou au branchement. |

### Règles de gestion

- **Seuils** : première alerte au seuil choisi (10, 15, 20 ou 30 %, 20 % par défaut), puis rappels à 10 % et 5 %. Chaque seuil n'alerte qu'une fois par décharge ; une chute de plusieurs seuils d'un coup (sortie de veille) ne donne qu'une alerte. Le branchement réinitialise les seuils.
- **Au lancement** de LetsWork, une batterie déjà sous le seuil déclenche l'alerte ; l'indicateur de charge n'apparaît qu'à un vrai branchement.
- **Lecture** : batterie interne via IOKit (`IOPSCopyPowerSourcesInfo`), mise à jour à chaque changement publié par macOS (`kIOPSNotifyAnyPowerSource`), sans interrogation périodique. Aucune autorisation n'est nécessaire.
- **Réglages** › Batterie : charge actuelle, indicateur de charge au branchement (activé par défaut), alerte de batterie faible (activée par défaut) et seuil de la première alerte.
- Sur un Mac sans batterie, rien n'est affiché et les réglages l'indiquent.

### Critères d'acceptation

- [ ] L'accueil affiche le même pourcentage que la barre des menus.
- [ ] Brancher le chargeur affiche « En charge » pendant ≈ 3 s, puis l'Island revient à son état précédent.
- [ ] Débrancher sous le seuil affiche l'alerte de batterie faible ; rebrancher la remplace par l'indicateur de charge.
- [ ] Sur batterie, l'alerte revient à 10 % puis à 5 %, une seule fois chacune.

---

## Exigences non fonctionnelles

| Domaine | Exigence |
|---|---|
| **Performance** | CPU < 1 % au repos et < 3 % pendant une animation ; mémoire < 100 Mo ; aucune boucle de polling serrée (préférer notifications et écouteurs). |
| **Énergie** | Animations suspendues quand l'Island est fermée ou l'écran éteint ; pas d'impact visible dans « Impact énergétique » du Moniteur d'activité. |
| **Fluidité** | Animations à 120 Hz sur écran ProMotion, sans saccade. |
| **Accessibilité** | Respect de « Réduire les animations » (fondus au lieu de ressorts) et du contraste élevé ; éléments étendus lisibles par VoiceOver. |
| **Localisation** | Français et anglais dès la v1 (String Catalog). |
| **Confidentialité** | Toutes les données restent sur le Mac ; aucune télémétrie sans consentement explicite. |
| **Résilience** | Chaque fonctionnalité est isolée : la panne d'une source (adaptateur média cassé par une mise à jour macOS, API calendrier indisponible) n'affecte ni l'Island ni les autres fonctionnalités. |
| **Compatibilité** | macOS 14 Sonoma minimum ; testé sur la dernière version majeure ; Apple Silicon prioritaire. |

---

## Jalons

| Jalon | Contenu | Livrable vérifiable | Statut |
|---|---|---|---|
| **M0 — Socle** | Fenêtre Island, ancrage sur l'encoche, états fermé/compact/étendu, survol, icône de barre de menus, réglages vides, lancement à l'ouverture de session. | L'Island s'ouvre au survol, au-dessus d'une app plein écran. | Fait |
| **M1 — Médias** | Intégration de mediaremote-adapter, modèle « Now Playing », vues compact/aperçu/étendu, contrôles, repli AppleScript. | Critères d'acceptation F1. | Validé avec Spotify (adaptateur et repli) ; vidéo dans un navigateur et Apple Music à vérifier |
| **M2 — HUD** | Spike touches/HUD natif, event tap, Core Audio, DisplayServices, vue HUD, assistant d'autorisation Accessibilité. | Critères d'acceptation F2. | Validé : clavier intégré et Logitech MX Keys S (volume, muet, luminosité) |
| **M3 — Calendrier** | EventKit, vues, alertes, détection de visio ; puis fournisseurs Google et Microsoft Graph. | Critères d'acceptation F3. | EventKit : accès et lecture des événements constatés sur la machine ; compact, alerte et « Rejoindre » à valider ; Google et Microsoft Graph à faire |
| **M4 — Finition** | Assistant de premier lancement, localisation, accessibilité, signature Developer ID, notarisation, mises à jour (Sparkle). | DMG notarisé installable sur un autre Mac. | À faire |
| **F4 — Notifications** | Lecture de la base du centre de notifications, pop-up dans l'Island, file d'attente, réglages et accès complet au disque. | Critères d'acceptation F4. | Validé sur macOS 27.0.1 : lecture, décodage et pop-up ; délai d'environ 5 s imposé par macOS |
| **F5 — Jeux** | Onglet Jeux : Morpion contre un bot (trois niveaux, score) et Glouton (labyrinthe, fantômes, clavier pendant la partie). | Critères d'acceptation F5. | Morpion codé et testé ; Glouton codé sans tests dédiés ; à vérifier à l'écran |
| **F6 — Batterie** | Lecture IOKit, niveau sur l'accueil, indicateur de charge au branchement, alerte de batterie faible avec rappels, réglages. | Critères d'acceptation F6. | Codé et testé ; niveau de l'accueil constaté à l'écran ; branchement et alerte vérifiés en rendu, à constater en débranchant |

---

## Questions ouvertes

1. **Distribution** : uniquement hors Mac App Store (imposé par les API privées et l'absence de sandbox), ou une version « allégée » App Store sans HUD ni MediaRemote ?
2. **Calendrier** : EventKit seul suffit-il pour v1 (comptes ajoutés à macOS), ou les connexions directes Google/Microsoft sont-elles nécessaires dès le départ (comptes d'entreprise bloquant Exchange) ?
3. **Écrans externes** : faut-il gérer la luminosité DDC/CI et l'affichage de l'Island sur un écran externe dès v1 ?
4. **Identité visuelle** : reproduire fidèlement le Dynamic Island d'iOS, ou créer un style propre à LetsWork ?
