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
Depuis le 7 novembre 2026, le projet iOS est **versionné** dans `ios/`, car Xcode Cloud exige un projet Xcode présent dans le dépôt. Il a été généré par `flutter create --platforms=ios --org org.sarcade`, puis complété par `tool/patch_ios.py` (idempotent, à relancer après une régénération du gabarit). `ios/.gitattributes` impose des fins de ligne LF, le projet étant édité sous Windows.

**Xcode Cloud** : `ios/ci_scripts/ci_post_clone.sh` (exécutable) installe Flutter (version figée, la même que sur le poste i9), CocoaPods et les paquets Dart, écrit `ios/Flutter/Generated.xcconfig` (`flutter build ios --config-only` avec le numéro de build `CI_BUILD_NUMBER`, `SARCADE_BUILD` et, si la variable secrète `GOOGLE_SERVICE_INFO_PLIST_B64` du workflow est fournie, les réglages Firebase du réveil), puis lance `pod install`. Signature automatique gérée par Xcode Cloud (équipe `34785R7XLK`). Numéros de build à partir de 2100.

Source de Xcode Cloud (depuis le 8 novembre 2026) : Xcode 27 ne trouve aucun dépôt sur notre GitLab auto-hébergé (« No source code repositories were found », reproduit avec un projet iOS natif de test ; rapport envoyé à Apple). Xcode Cloud lit donc une **copie privée sur gitlab.com**, `https://gitlab.com/sdubos/sarcade-app-xcode`, alimentée par un miroir en poussée de `sarcade/sarcade-app` (Settings › Repository › Mirroring repositories, branches protégées seulement, donc `main` ; authentification par clé SSH, clé de déploiement en écriture côté gitlab.com). On ne pousse jamais directement sur gitlab.com. `ios/Runner.xcodeproj/xcshareddata/xcodecloud/manifest.json` (créé par Xcode) relie le projet au produit Xcode Cloud « Runner ».

Workflow « Default » (App Store Connect › Xcode Cloud) :
- espace de travail `ios/Runner.xcworkspace`, schéma `Runner`, Xcode et macOS « Latest Release », compilation propre ;
- démarrage à la main sur n'importe quelle branche, ou automatique sur `main` quand `lib/`, `ios/`, `assets/` ou `pubspec.yaml` changent (un build en cours est annulé par le suivant) ;
- action Archive - iOS, distribution App Store Connect, puis post-action TestFlight Internal Testing vers « SARCADE interne » ;
- variable secrète `GOOGLE_SERVICE_INFO_PLIST_B64` (réveil par Firebase).

Premier build réussi : 2103 (8 novembre 2026, `main@04889d1`), vérifié sur iPhone. Le 2102 a échoué sur une erreur passagère de GitHub (504) au téléchargement de `WebRTC.xcframework.zip` pendant `pod install` : relancer le build (Rebuild) suffit.

**Codemagic** (en secours depuis le 8 novembre 2026, démarrage à la main seulement ; mis en place le 7 novembre 2026, `codemagic.yaml`, workflow `ios-testflight`) : même préparation que Xcode Cloud, car le workflow lance `ios/ci_scripts/ci_post_clone.sh` avec les variables de Codemagic (le script réutilise le Flutter 3.47.9 déjà installé par Codemagic). Dépôt cloné en HTTPS depuis `https://gitlab.sdubos.com/sarcade/sarcade-app.git` avec un jeton de déploiement GitLab en lecture ; Cloudflare Access laisse passer les machines de Codemagic (stratégie « GitLab - Codemagic (plages officielles) », plages de `https://codemagic.io/api/v3/meta`). Signature automatique par l'intégration Developer Portal nommée « SARCADE » dans Codemagic (clé App Store Connect, rôle App Manager) : `app-store-connect fetch-signing-files --type IOS_APP_STORE --create` avec la clé privée du certificat Apple Distribution (`CERTIFICATE_PRIVATE_KEY`, groupe de variables `code_signing`). Numéro de build = dernier numéro TestFlight + 1, jamais moins de 2100. Envoi à TestFlight, test interne seulement (`testFlightInternalTestingOnly`) ; le groupe interne « SARCADE interne » reçoit chaque nouveau build automatiquement, donc pas de `beta_groups` dans `codemagic.yaml` (App Store Connect refuse d'y assigner un build : « Cannot add internal group to a build »). Réveil par Firebase si la variable secrète `GOOGLE_SERVICE_INFO_PLIST_B64` (groupe `firebase`) est fournie. Démarrage : à la main dans Codemagic. Aucun webhook GitLab n'est configuré (vérifié le 8 novembre 2026) : les déclencheurs de `codemagic.yaml` (poussée sur `main` touchant `lib/`, `ios/`, `assets/` ou `pubspec.*`) ne servent que si l'on ajoute ce webhook.

**Swift Package Manager désactivé** pour ce projet (`pubspec.yaml`, `flutter: config: enable-swift-package-manager: false`, 8 novembre 2026) : depuis Flutter 3.47, les plugins passaient par SwiftPM et leurs dépôts GitHub (CwlCatchException, de `speech_to_text`, Firebase…) ; Xcode Cloud demandait alors de connecter un compte GitHub. Tous les plugins passent par CocoaPods (`pod install` de `ci_post_clone.sh`).

`tool/patch_ios.py` complète `Info.plist` :
- textes d'autorisation pour la localisation, le réseau local et la photothèque
- exception App Transport Security pour le HTTP non chiffré, nécessaire tant que le serveur V0.1 est joint en `http://IP:8000` (à retirer avec le passage en HTTPS)
- nom affiché « SARCADE »

Les étapes sont dans `.github/workflows/ios-build.yml`. Sur une pull request, le job `ios-build` de la CI compile sans signature (preuve de compilation). La version signée et envoyée à TestFlight est construite **chaque nuit sur `main`** et à la demande (Actions › iOS nightly › Run workflow, `.github/workflows/ios-nightly.yml`), avec la clé d'API App Store Connect des secrets GitHub ; repli sur un Mac Intel si aucune machine arm64 n'est attribuée ; numéro de build = numéro du lancement + 2000. Un lancement sur une autre branche ne fait que compiler. Si aucune version n'est arrivée dans TestFlight depuis 48 h, le ticket « Pas de version iPhone depuis 48 h » (étiquette `ci`) est ouvert, puis fermé automatiquement (`tool/ios_watch.py`).
