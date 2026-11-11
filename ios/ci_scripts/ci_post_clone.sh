#!/bin/bash
# Xcode Cloud: runs right after the clone, before xcodebuild (card « iPhone par
# Xcode Cloud : projet ios/ versionné et ci_post_clone.sh », 7 Nov 2026).
#
# Prepares what the committed ios/ project needs and Git does not hold:
# Flutter (pinned), Dart packages, ios/Flutter/Generated.xcconfig (build number,
# --dart-define values) and the CocoaPods workspace (ios/Pods).
#
# Xcode Cloud variables used: CI_PRIMARY_REPOSITORY_PATH, CI_BUILD_NUMBER,
# CI_COMMIT, CI_BRANCH (or CI_TAG). Codemagic (codemagic.yaml) runs this same
# script and sets these variables from its own (CM_BUILD_DIR, CM_COMMIT...). Optional secret variable of the workflow:
# GOOGLE_SERVICE_INFO_PLIST_B64 (GoogleService-Info.plist in base64) for the
# iPhone wake-up by Firebase; without it the build goes on, unwoken.
#
# Never print a secret: no `set -x`, values only go to Generated.xcconfig.
set -euo pipefail

FLUTTER_VERSION="3.47.9"   # same as the i9 (flutter --version), raise together

cd "${CI_PRIMARY_REPOSITORY_PATH:?not run by Xcode Cloud}"

echo "== Flutter ${FLUTTER_VERSION}"
if command -v flutter >/dev/null 2>&1 && flutter --version 2>/dev/null | grep -q "^Flutter ${FLUTTER_VERSION} "; then
  echo "pinned Flutter already on PATH (Codemagic): $(command -v flutter)"
else
  if [ ! -x "$HOME/flutter/bin/flutter" ]; then
    git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
  fi
  export PATH="$HOME/flutter/bin:$PATH"   # first: the pinned Flutter wins over any other
fi
flutter config --no-analytics >/dev/null
flutter --version
flutter precache --ios

echo "== CocoaPods (also needed by flutter build --config-only)"
if ! command -v pod >/dev/null 2>&1; then
  export HOMEBREW_NO_AUTO_UPDATE=1
  brew install cocoapods
fi
pod --version

echo "== Dart packages"
flutter pub get

BUILD_NUMBER="${CI_BUILD_NUMBER:?CI_BUILD_NUMBER missing}"
COMMIT="${CI_COMMIT:-unknown}"
REF="${CI_BRANCH:-${CI_TAG:-detached}}"
DEFINES=(
  "--dart-define=SARCADE_BUILD_NUMBER=${BUILD_NUMBER}"
  "--dart-define=SARCADE_BUILD=${REF}@${COMMIT:0:7}"
)

echo "== Firebase (iPhone wake-up)"
if [ -n "${GOOGLE_SERVICE_INFO_PLIST_B64:-}" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  plist="$tmp/GoogleService-Info.plist"
  printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_B64" | base64 -D > "$plist"
  value() { plutil -extract "$1" raw -o - "$plist"; }
  DEFINES+=(
    "--dart-define=SARCADE_FCM_IOS_API_KEY=$(value API_KEY)"
    "--dart-define=SARCADE_FCM_IOS_APP_ID=$(value GOOGLE_APP_ID)"
    "--dart-define=SARCADE_FCM_SENDER_ID=$(value GCM_SENDER_ID)"
    "--dart-define=SARCADE_FCM_PROJECT_ID=$(value PROJECT_ID)"
  )
  rm -rf "$tmp"
  echo "Firebase wake-up built in"
else
  echo "warning: GOOGLE_SERVICE_INFO_PLIST_B64 not set, iPhone not woken by Firebase"
fi

echo "== Xcode configuration (build ${BUILD_NUMBER}, ${REF}@${COMMIT:0:7})"
flutter build ios --release --config-only --build-number="$BUILD_NUMBER" "${DEFINES[@]}"

echo "== Pods"
cd ios
# One retry after a short pause, only on failure: pod install downloads some
# pods from GitHub (WebRTC.xcframework.zip), and a transient 504 failed build
# 2102 (8 Nov 2026). A second failure stops the build as before.
if ! pod install; then
  POD_RETRY_DELAY="${POD_RETRY_DELAY:-30}"
  echo "pod install failed; second try in ${POD_RETRY_DELAY} s"
  sleep "$POD_RETRY_DELAY"
  pod install
fi

echo "== ready for xcodebuild"
