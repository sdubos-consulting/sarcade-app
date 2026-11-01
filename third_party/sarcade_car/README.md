# sarcade_car

Plugin local de SARCADE pour **Android Auto**.

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

## Lot 17, étape 2b : CarPlay (inactif tant qu'Apple n'a pas accordé l'autorisation)
- `ios/Classes/SarcadeCarPlaySceneDelegate.swift` : mêmes onglets (`CPTabBarTemplate`,
  listes), « SOS » dans la barre de navigation de chaque onglet avec
  confirmation (`CPAlertTemplate`), fiches (`CPInformationTemplate`) ; « Naviguer »
  ouvre Plans ; « Lire » par la synthèse vocale ; pas de dictée (CarPlay ne la
  donne pas à cette catégorie : réponse par Siri, lot 1c).
- `ios/Classes/SarcadeCarPlugin.swift` : même canal que sur Android.
- La scène CarPlay et l'autorisation `com.apple.developer.carplay-public-safety`
  ne sont déclarées par `tool/patch_ios.py` qu'avec `SARCADE_CARPLAY=1`, à
  activer dans la CI quand Apple aura accordé l'autorisation (profil
  d'approvisionnement à régénérer) ; d'ici là, le code est compilé mais iOS ne
  l'appelle jamais.

## Essai
Desktop Head Unit (DHU) sur PC, téléphone en USB, puis voiture : mode
développeur d'Android Auto, « Sources inconnues » pour un APK hors Play.
