# sarcade_car

Plugin local de SARCADE : déclare l'application à **Android Auto** comme
messagerie (lot 1b de la carte « CarPlay et Android Auto », 1er novembre 2026).

- `android/src/main/AndroidManifest.xml` : `com.google.android.gms.car.application`
  vers `res/xml/automotive_app_desc.xml` (`<uses name="notification"/>`) ;
  fusionné dans le manifeste de l'application, `tool/patch_android.py` reste
  inchangé.
- Aucun code Dart à appeler : les notifications au format conversation
  (MessagingStyle, Répondre, Lu) sont construites par l'application.

Essai : Desktop Head Unit (DHU) sur PC, téléphone en USB, puis voiture
(mode développeur d'Android Auto, « Sources inconnues » pour un APK hors Play).
