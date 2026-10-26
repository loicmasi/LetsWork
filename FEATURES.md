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
  - onglets de l'état étendu, en haut à gauche à côté de l'encoche : **Accueil** (date, heure, puis « En lecture : Titre — Artiste » ou « En pause : … » quand un média est en cours — un clic ouvre l'onglet Multimédia — sinon « Aucune activité pour le moment » ; à droite, un mini-calendrier du mois à la manière du widget Calendrier de macOS, qui ouvre l'onglet Calendrier) et **Multimédia** (lecteur, ou « Aucune lecture en cours ») ; le calendrier (F3) y ajoutera son onglet. L'onglet choisi est conservé d'une ouverture à l'autre, en commençant par Accueil ;
  - swipe horizontal à deux doigts sur l'Island → bascule entre les activités (média ↔ agenda).
- **Clics traversants** : les zones transparentes de la fenêtre ne doivent jamais bloquer les clics sur la barre de menus ou les fenêtres situées dessous.
- **Multi-écrans** : réglage « Afficher sur » : écran avec encoche (défaut) / écran principal / écran sous la souris / tous les écrans.
- **Masquage automatique** : l'Island se masque pendant les partages d'écran et quand une application plein écran le demande (option, ex. jeux, Keynote).

### Arbitrage des activités

Plusieurs fonctionnalités peuvent vouloir s'afficher en même temps. Un **coordinateur d'activités** décide de ce qui est montré, selon cette priorité :

1. **HUD** (volume / luminosité) — interrompt tout, temporaire ;
2. **Alerte calendrier** (réunion dans ≤ 5 min / en cours) — temporaire, puis retour à l'activité de fond ;
3. **Changement de piste** — compact pendant ≈ 3 s ;
4. **Activité de fond** : lecture média en cours, sinon prochain événement, sinon état fermé.

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

### Affichage

| État | Contenu |
|---|---|
| **Compact** | Aile gauche : pochette miniature (ou icône de la source). Aile droite : égaliseur animé si lecture en cours, icône pause sinon. |
| **Étendu** (onglet Multimédia) | Pochette grand format, titre, artiste/chaîne, album, icône de la source, barre de progression interactive (temps écoulé / durée), boutons précédent / lecture-pause / suivant. Teinte d'accent dérivée de la couleur dominante de la pochette. Sur la partie écoulée de la barre, trois couches de dômes animées défilent en sens opposés, chacune dans une nuance de la pochette (discrète, intermédiaire, contrastée) ; elles s'aplatissent et se figent en pause, et restent immobiles si « Réduire les animations » est activé. |
| **Changement de piste** | Passage en compact enrichi (titre défilant) pendant ≈ 3 s. |

### Sources et méthodes de récupération

| Source | Méthode principale | Informations | Contrôles |
|---|---|---|---|
| Toute app publiant dans le « Now Playing » de macOS (Apple Music, Spotify, Podcasts, TV, navigateurs, VLC, IINA…) | **MediaRemote** (framework privé) via [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) | titre, artiste, album, durée, position, pochette, état lecture, bundle id de l'app source | lecture, pause, bascule, suivant, précédent, seek |
| Safari, Chrome, Edge, Arc, Brave, Firefox | Même canal : les navigateurs exposent la Media Session API des pages (YouTube, Netflix, SoundCloud…) au Now Playing de macOS | titre de la vidéo, chaîne, durée, position, vignette (selon le site) | idem (selon ce que la page déclare) |
| Spotify, Apple Music (complément) | **AppleScript / Scripting Bridge** + notifications distribuées `com.spotify.client.PlaybackStateChanged` et `com.apple.Music.playerInfo` | état de **chaque** app, même quand elle n'est pas la source « active » | lecture, pause, suivant, précédent, position |

**Pourquoi un adaptateur ?** Depuis macOS 15.4, le framework MediaRemote n'est plus utilisable directement depuis une application tierce. `mediaremote-adapter` contourne la restriction en faisant exécuter un petit framework par `/usr/bin/perl`, binaire système autorisé, et diffuse les changements en JSON sur la sortie standard (`stream`). Les commandes passent par `send <id>` et `seek <µs>`. Le canal reste **non officiel** : il peut casser à chaque mise à jour de macOS ; il doit donc être isolé derrière une interface, avec le canal AppleScript comme repli.

### Règles de gestion

- **Source affichée** : celle que macOS considère comme « Now Playing ». Si plusieurs apps sont en pause, la dernière active reste affichée en état étendu ; en compact, rien n'est affiché tant que rien ne joue (option : garder la dernière source visible).
- **Identification de la source** : icône et nom résolus depuis le bundle id (`NSWorkspace.urlForApplication(withBundleIdentifier:)`). Pour un navigateur, afficher l'icône du navigateur ; si le titre de la page/le domaine est disponible, l'afficher en sous-titre.
- **Position de lecture** : interpolée localement entre deux mises à jour (position + vitesse + horodatage) pour une barre de progression fluide, sans interroger la source en continu.
- **Pochette absente** : icône de l'application source sur fond flouté.
- **Fin de lecture / fermeture de l'app source** : retour à l'activité suivante selon l'arbitrage F0 après ≈ 5 s.

### Autorisations

- **Automatisation** (Apple Events) vers Spotify et Music, demandée uniquement si le canal AppleScript est utilisé.
- Aucune autorisation n'est nécessaire pour le canal MediaRemote via l'adaptateur.

### Critères d'acceptation

- [ ] Lecture dans Apple Music : titre, artiste, pochette et progression s'affichent en < 1 s après le démarrage.
- [ ] Lecture dans Spotify : idem, et les contrôles agissent sur Spotify.
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
- Bouton « J'aime » / ajout à une playlist (Spotify Web API, Apple Music via AppleScript).
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

### Affichage

| État | Contenu |
|---|---|
| **Compact** (activité de fond, si aucun média ne joue) | Pastille de couleur du calendrier + titre court + « dans 12 min » / « en cours ». |
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

### Décisions et limites (M3)

- **Sources** : EventKit seul pour l'instant, derrière l'interface `CalendarProvider`. Les fournisseurs Google Calendar et Microsoft Graph demandent d'enregistrer une application cliente OAuth chez Google Cloud et Microsoft Entra ID ; ils restent à faire (voir Questions ouvertes).
- **Compact** : l'événement apparaît une heure avant son début et reste affiché pendant son déroulement ; la lecture d'un média reste prioritaire. Les événements sur la journée entière n'apparaissent pas en compact.
- **Alerte** : une seule fois par événement et par lancement de l'app ; délai réglable (1, 5, 10 ou 15 min, 5 par défaut).
- **Accueil** : ligne « En cours : Titre » ou « Prochain : Titre · dans 12 min », et mini-calendrier du mois (mois en rouge, semaine commençant le lundi, week-ends grisés, jour actuel dans une pastille rouge) ; les deux ouvrent l'onglet Calendrier.
- **Accès** : demandé depuis l'onglet Calendrier ou les réglages, jamais au lancement.
- **« Rejoindre »** : ouvre le lien https ; l'app de visio le prend en charge si elle est installée.
- **Calendriers affichés** et **journées entières masquées** : réglables dans Réglages › Calendrier.

### Évolutions (hors v1)

- Rappels (`EKReminder`), création rapide d'événement.
- Statut « occupé » : passer le Mac en mode Concentration pendant les réunions.

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

---

## Questions ouvertes

1. **Distribution** : uniquement hors Mac App Store (imposé par les API privées et l'absence de sandbox), ou une version « allégée » App Store sans HUD ni MediaRemote ?
2. **Calendrier** : EventKit seul suffit-il pour v1 (comptes ajoutés à macOS), ou les connexions directes Google/Microsoft sont-elles nécessaires dès le départ (comptes d'entreprise bloquant Exchange) ?
3. **Écrans externes** : faut-il gérer la luminosité DDC/CI et l'affichage de l'Island sur un écran externe dès v1 ?
4. **Identité visuelle** : reproduire fidèlement le Dynamic Island d'iOS, ou créer un style propre à LetsWork ?
