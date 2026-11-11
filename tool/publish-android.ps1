# Publication Android depuis l'i9 (carte « Android : publication automatique
# sur Google Play, reprise depuis l'i9 », validée le 8 novembre 2026).
#
# Construit l'AAB signé de gitlab/main dans un worktree neuf, comme le
# faisait la CI GitHub, puis l'envoie sur la piste « Test interne » de
# Google Play. Lancé par Claude juste après chaque poussée de main vers
# gitlab. Windows PowerShell 5.1 ; peut être relancé sans risque.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\publish-android.ps1 [-DryRun] [-Status auto|draft|completed]
#
# -DryRun : tout sauf l'envoi à Google Play (l'AAB est gardé).
# -Status : « auto » (par défaut) publie aussitôt la version pour les
#           testeurs internes, et ne la laisse en brouillon que si Google le
#           refuse (application encore en brouillon) ; « draft » ou
#           « completed » pour forcer.
#
# Secrets lus dans C:\dev\secrets\android\ (jamais affichés) :
#   sarcade-upload.jks, key.properties, play-service-account.json,
#   google-services.json.
param(
  [switch]$DryRun,
  [ValidateSet('auto', 'draft', 'completed')][string]$Status = 'auto'
)
$ErrorActionPreference = 'Continue'
$repo = 'C:\dev\sarcade\sarcade-app'
$sec  = 'C:\dev\secrets\android'
$out  = 'C:\dev\sarcade\publications\android'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$wt   = "C:\dev\sarcade\wt\android-publish-$stamp"

function Fail([string]$msg) { Write-Host "ÉCHEC : $msg" -ForegroundColor Red; throw $msg }

New-Item -ItemType Directory -Force $out | Out-Null
Start-Transcript -Path (Join-Path $out "publication-$stamp.log") | Out-Null
try {
  foreach ($f in 'sarcade-upload.jks', 'key.properties', 'play-service-account.json', 'google-services.json') {
    if (-not (Test-Path (Join-Path $sec $f))) { Fail "secret absent : $sec\$f" }
  }

  # Anciens worktrees de publication (verrous Windows possibles : on ignore).
  Get-ChildItem 'C:\dev\sarcade\wt' -Directory -Filter 'android-publish-*' -ErrorAction SilentlyContinue | ForEach-Object {
    git -C $repo worktree remove --force $_.FullName 2>$null
  }
  git -C $repo worktree prune

  git -C $repo fetch -q gitlab
  if ($LASTEXITCODE -ne 0) { Fail 'git fetch gitlab' }
  $sha = (git -C $repo rev-parse --short gitlab/main).Trim()
  Write-Host "=== gitlab/main = $sha"
  git -C $repo worktree add -q --detach $wt gitlab/main
  if ($LASTEXITCODE -ne 0) { Fail "worktree $wt" }
  Set-Location $wt

  Write-Host '=== préparation Android'
  flutter create --platforms=android --org org.sarcade --no-pub . | Out-Null
  Remove-Item -Force -ErrorAction SilentlyContinue 'test\widget_test.dart'
  $props = @{}
  foreach ($line in [IO.File]::ReadAllLines((Join-Path $sec 'key.properties'))) {
    $i = $line.IndexOf('=')
    if ($i -gt 0) { $props[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1) }
  }
  if (-not $props['storePassword'] -or -not $props['keyAlias']) { Fail 'key.properties incomplet' }
  $env:SARCADE_KEYSTORE = Join-Path $sec 'sarcade-upload.jks'
  $env:SARCADE_KEYSTORE_PASSWORD = $props['storePassword']
  $env:SARCADE_KEY_ALIAS = $props['keyAlias']
  python tool/patch_android.py
  if ($LASTEXITCODE -ne 0) { Fail 'patch_android.py' }
  flutter pub get | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get' }

  # Réveil par Firebase : identifiants du projet en --dart-define (comme la CI).
  # Script à part : PowerShell 5.1 retire les guillemets d'un « python -c ».
  $defines = @(python -I tool/fcm_defines.py (Join-Path $sec 'google-services.json') 2>$null)
  if ($LASTEXITCODE -ne 0 -or $defines.Count -ne 4) { Fail 'google-services.json illisible' }

  $key = Join-Path $sec 'play-service-account.json'
  $version = (uv run --quiet --script tool/play_publish.py next-version --key $key | Select-Object -Last 1)
  if ($LASTEXITCODE -ne 0 -or $version -notmatch '^\d+$') { Fail 'numéro de version Google Play' }
  Write-Host "=== versionCode $version"

  Write-Host '=== flutter build appbundle'
  flutter build appbundle --release "--build-number=$version" "--dart-define=SARCADE_BUILD_NUMBER=$version" "--dart-define=SARCADE_BUILD=main@$sha" @defines 2>&1 |
    Select-String -Pattern 'Built |error|Error|FAILURE|What went wrong' | ForEach-Object { $_.Line }
  $aab = 'build\app\outputs\bundle\release\app-release.aab'
  if (-not (Test-Path $aab)) { Fail 'AAB non construit' }
  $kept = Join-Path $out "sarcade-$version-$sha.aab"
  Copy-Item -Force $aab $kept
  Write-Host "AAB : $kept ($([math]::Round((Get-Item $kept).Length / 1MB, 1)) Mo)"

  if ($DryRun) { Write-Host '=== -DryRun : pas d''envoi à Google Play' -ForegroundColor Yellow }
  else {
    Write-Host "=== envoi à Google Play (Test interne, $Status)"
    uv run --quiet --script tool/play_publish.py upload --key $key --aab $kept --version $version --status $Status --name "main@$sha"
    if ($LASTEXITCODE -ne 0) { Fail 'envoi à Google Play' }
    Write-Host "Envoyé : versionCode $version (main@$sha) sur « Test interne » (statut indiqué ci-dessus)." -ForegroundColor Green
  }
}
finally {
  foreach ($v in 'SARCADE_KEYSTORE', 'SARCADE_KEYSTORE_PASSWORD', 'SARCADE_KEY_ALIAS') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
  Set-Location $repo
  git -C $repo worktree remove --force $wt 2>$null
  Stop-Transcript | Out-Null
}
