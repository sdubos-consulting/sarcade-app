# sarcade_car

Plugin local de SARCADE pour **Android Auto** et **CarPlay**.

## Lot 1b (1er novembre 2026) : messagerie par notifications
- `android/src/main/AndroidManifest.xml` : `com.google.android.gms.car.application`
  vers `res/xml/automotive_app_desc.xml` (`<uses name="notification"/>`).
- Les notifications au format conversation (MessagingStyle, Répondre, Lu)
  sont construites par l'application (`lib/src/features/car/car_android.dart`).

## Lot 17 (1er novembre 2026) : écran SARCADE avec onglets
Carte « Voiture : vraie interface SARCADE avec onglets », choix 1 à 7 validés.
- Catégorie **points d'intérêt** (`androidx.car.app.category.POI`), service
  `SarcadeCarAppService`, `<uses name="template"/>`, `minCarApiLevel` 1.
- Bibliothèque **Car App Library 1.7.0** (`androidx.car.app:app`, dépendance
  Gradle du plugin), code **Kotlin** (`android/src/main/kotlin`).
- Onglets (`TabTemplate`, niveau d'API voiture 6 et plus) : **Messages**,
  **Ordres**, **Points**, **Équipe** ; bouton rond rouge **SOS** dans chaque
  onglet, avec confirmation. Hôtes plus anciens : une liste par rubrique,
  barre d'actions « Rubriques » et « SOS ».
- Aucune saisie au clavier : lecture à voix haute (synthèse vocale du
  téléphone), réponse dictée (reconnaissance vocale du téléphone).
- « Naviguer » : application de navigation de la voiture (Google Maps, Waze).
- Données et textes écrits par l'application (`lib/src/features/car/car_screen.dart`,
  textes `car.*` de `strings.dart`) par le canal `org.sarcade.car/screen` ;
  les actions du conducteur attendent dans les préférences privées de
  l'application jusqu'à ce qu'elle les lise (aucune perte si elle ne tourne pas).

## Lot 17, étape 2b : CarPlay
- `ios/Classes/SarcadeCarPlaySceneDelegate.swift` : mêmes onglets (`CPTabBarTemplate`,
  listes), « SOS » dans la barre de navigation de chaque onglet avec
  confirmation (`CPAlertTemplate`) ; « Naviguer » ouvre Plans ; « Lire » par
  la synthèse vocale.
- `ios/Classes/SarcadeCarPlugin.swift` : même canal que sur Android.

## CarPlay, catégorie « Communication » (9 novembre 2026)
Accord d'Apple du 9 novembre 2026 (« CarPlay Communication App »), capacité
cochée sur l'identifiant `org.sarcade.sarcadeApp` avec « Siri ».
- Autorisations `com.apple.developer.carplay-communication` et
  `com.apple.developer.siri`, scène CarPlay, `INIntentsSupported` et texte
  d'usage de Siri : écrits par `tool/patch_ios.py` (actifs par défaut,
  `SARCADE_CARPLAY=0` pour un build sans CarPlay).
- Écrans limités à ce que la catégorie permet : onglets, listes et alertes.
  Une conversation et un ordre s'ouvrent en liste (plus de
  `CPInformationTemplate`), comme sur Android Auto : « Lire les nouveaux
  messages », un message par ligne lu au toucher ; Accepter, Refuser, Je suis
  arrivé, Terminé, Naviguer.
- **Siri par un module séparé** (essai du 9 novembre 2026 : Siri ne passait pas
  par l'application elle-même) : extension « Intents » `ios/SarcadeIntents`
  (`org.sarcade.sarcadeApp.SarcadeIntents`), ajoutée au projet Xcode par
  `tool/ios_intents.py` (appelé par `tool/patch_ios.py`) : envoyer
  (`INSendMessageIntent`, destinataire = une partie du titre d'une
  conversation de l'écran voiture) et marquer comme lu
  (`INSetMessageAttributeIntent`). Données partagées avec l'application par le
  groupe d'applications `group.org.sarcade.sarcadeApp` (mêmes clés que
  l'écran voiture) ; un message dicté devient une action « reply » ;
  l'application, si elle tourne, la prend aussitôt (notification Darwin
  `org.sarcade.car.actions`), sinon à son prochain réveil. Noms parlés de
  l'application (`INAlternativeAppNames`). Autorisation de Siri demandée une
  fois par l'application.
- Notifications SARCADE visibles dans CarPlay (`allowInCarPlay`).
- Pas de Mac : vérification par Xcode Cloud, TestFlight, puis la voiture.

## Essai
Desktop Head Unit (DHU) sur PC, téléphone en USB, puis voiture : mode
développeur d'Android Auto, « Sources inconnues » pour un APK hors Play.
