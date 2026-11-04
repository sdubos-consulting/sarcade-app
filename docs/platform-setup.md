# Préparation des plateformes

Le dépôt contient le code applicatif commun. Générer les runners Flutter avec :

```
flutter create --platforms=android,ios,web,windows,linux,macos .
flutter pub get
```

## Localisation
Android doit déclarer ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION. iOS doit déclarer NSLocationWhenInUseUsageDescription. Le suivi en arrière-plan sera traité séparément car il exige des permissions et politiques spécifiques.

## Démarrage développement
```
flutter run --dart-define=SARCADE_SERVER_URL=http://ADRESSE_SERVEUR:8000 --dart-define=SARCADE_EVENT_ID=ID_EVENEMENT --dart-define=SARCADE_DEVICE_ID=TERMINAL_01
```

Le style MapLibre de démonstration n'est pas destiné à la production. La stratégie tuiles/styles SARCADE et le téléchargement offline seront définis dans le chantier Offline First.

## iOS
La CI génère le projet iOS (`flutter create --platforms=ios --org org.sarcade`), puis `tool/patch_ios.py` complète `Info.plist` :
- textes d'autorisation pour la localisation, le réseau local et la photothèque
- exception App Transport Security pour le HTTP non chiffré, nécessaire tant que le serveur V0.1 est joint en `http://IP:8000` (à retirer avec le passage en HTTPS)
- nom affiché « SARCADE »

Les étapes sont dans `.github/workflows/ios-build.yml`. Sur une pull request, le job `ios-build` de la CI compile sans signature (preuve de compilation). La version signée et envoyée à TestFlight est construite **chaque nuit sur `main`** et à la demande (Actions › iOS nightly › Run workflow, `.github/workflows/ios-nightly.yml`), avec la clé d'API App Store Connect des secrets GitHub ; repli sur un Mac Intel si aucune machine arm64 n'est attribuée ; numéro de build = numéro du lancement + 2000. Un lancement sur une autre branche ne fait que compiler. Si aucune version n'est arrivée dans TestFlight depuis 48 h, le ticket « Pas de version iPhone depuis 48 h » (étiquette `ci`) est ouvert, puis fermé automatiquement (`tool/ios_watch.py`).
