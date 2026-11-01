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

## Essai
Desktop Head Unit (DHU) sur PC, téléphone en USB, puis voiture : mode
développeur d'Android Auto, « Sources inconnues » pour un APK hors Play.
