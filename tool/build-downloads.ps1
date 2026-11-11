# Fichiers de la page Téléchargements du serveur SARCADE (carte « Windows :
# publier l'installateur sans GitHub », validée le 8 novembre 2026), construits
# sur l'i9 comme le faisait la CI GitHub (suspendue depuis le 6 novembre 2026) :
# installeur Windows (Inno Setup), APK Android signé avec la clé d'envoi, et
# archive des sources de l'application. Windows PowerShell 5.1 ; relançable :
# rien n'est refait si le dossier du commit est déjà complet.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\build-downloads.ps1 [-Force]
#
# Résultat : C:\dev\sarcade\publications\downloads\<commit>\ avec
#   sarcade-windows-setup.exe, sarcade-android.apk,
#   sarcade-app-sources-<commit>.tar.gz et app-files.json (entrées du
#   manifeste, complété par tool\nas\publish-registry.ps1 du serveur).
# Numéro de build : celui de la dernière version Android publiée depuis l'i9.
# Signature Windows : faite par tool\sign-windows.ps1 quand la signature Azure
# est rangée dans C:\dev\secrets\windows\ ; sinon installeur non signé (la
# page Téléchargements l'explique).
param([switch]$Force)
$ErrorActionPreference = 'Continue'
# nuget.exe (winget, 9 novembre 2026) : exigé par la partie Windows de flutter_tts.
$wingetLinks = "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
if (($env:Path -split ';') -notcontains $wingetLinks) { $env:Path += ";$wingetLinks" }
$repo = 'C:\dev\sarcade\sarcade-app'
$sec  = 'C:\dev\secrets\android'
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
$wt   = "C:\dev\sarcade\wt\downloads-build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

function Fail([string]$msg) { Write-Host "ÉCHEC : $msg" -ForegroundColor Red; throw $msg }
function Entry($kind, $file, $version, $build, [bool]$signed) {
  $i = Get-Item $file
  [ordered]@{ kind = $kind; name = $i.Name; size = $i.Length; sha256 = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLower();
              version = $version; build = $build; date = (Get-Date -Format 'yyyy-MM-dd'); signed = $signed }
}

git -C $repo fetch -q gitlab
if ($LASTEXITCODE -ne 0) { Fail 'git fetch gitlab' }
$sha = (git -C $repo rev-parse --short gitlab/main).Trim()
$out = "C:\dev\sarcade\publications\downloads\$sha"
if ((Test-Path "$out\app-files.json") -and -not $Force) { Write-Host "Déjà construit : $out" -ForegroundColor Green; return }
if (-not (Test-Path $iscc)) { Fail "Inno Setup absent : $iscc (winget install --id JRSoftware.InnoSetup --version 6.7.1 --scope user)" }
foreach ($f in 'sarcade-upload.jks', 'key.properties', 'google-services.json') {
  if (-not (Test-Path (Join-Path $sec $f))) { Fail "secret absent : $sec\$f" }
}
New-Item -ItemType Directory -Force $out | Out-Null
Remove-Item -Force "$out\*" -ErrorAction SilentlyContinue

$number = 0
Get-ChildItem 'C:\dev\sarcade\publications\android' -Filter 'sarcade-*.aab' -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.Name -match '^sarcade-(\d+)-') { $number = [math]::Max($number, [int]$Matches[1]) }
}
$build = "main@$sha"
Write-Host "=== gitlab/main = $sha, build $number"

try {
  Get-ChildItem 'C:\dev\sarcade\wt' -Directory -Filter 'downloads-build-*' -ErrorAction SilentlyContinue | ForEach-Object {
    git -C $repo worktree remove --force $_.FullName 2>$null
  }
  git -C $repo worktree prune
  git -C $repo worktree add -q --detach $wt gitlab/main
  if ($LASTEXITCODE -ne 0) { Fail "worktree $wt" }
  Set-Location $wt
  $core = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
  $version = "$core+$number"

  Write-Host '=== sources'
  $src = Join-Path $out "sarcade-app-sources-$sha.tar.gz"
  git -C $repo archive --format=tar.gz --prefix=sarcade-app/ -o $src gitlab/main
  if ($LASTEXITCODE -ne 0) { Fail 'git archive' }

  Write-Host '=== préparation Windows et Android'
  flutter create "--platforms=windows,android" --org org.sarcade --no-pub . | Out-Null
  Remove-Item -Force -ErrorAction SilentlyContinue 'test\widget_test.dart'
  python tool/patch_windows.py
  if ($LASTEXITCODE -ne 0) { Fail 'patch_windows.py' }
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

  Write-Host '=== flutter build windows'
  flutter build windows --release "--dart-define=SARCADE_BUILD_NUMBER=$number" "--dart-define=SARCADE_BUILD=$build" 2>&1 |
    Select-String -Pattern 'Built |error|Error|FAILED' | ForEach-Object { $_.Line }
  $exe = 'build\windows\x64\runner\Release\sarcade_app.exe'
  if (-not (Test-Path $exe)) { Fail 'build windows' }
  $signer = Join-Path $PSScriptRoot 'sign-windows.ps1'
  $canSign = (Test-Path $signer) -and (Test-Path 'C:\dev\secrets\windows\azure-signing.json')
  if ($canSign) {
    powershell -NoProfile -ExecutionPolicy Bypass -File $signer -Files (Resolve-Path $exe).Path
    if ($LASTEXITCODE -ne 0) { Fail 'signature de sarcade_app.exe' }
  }
  $env:SARCADE_VERSION = $core
  & $iscc /Q tool\windows_installer.iss
  if ($LASTEXITCODE -ne 0) { Fail 'Inno Setup' }
  $setup = 'build\installer\sarcade-windows-setup.exe'
  if ($canSign) {
    powershell -NoProfile -ExecutionPolicy Bypass -File $signer -Files (Resolve-Path $setup).Path
    if ($LASTEXITCODE -ne 0) { Fail 'signature de l''installeur' }
  }
  Copy-Item -Force $setup "$out\sarcade-windows-setup.exe"

  Write-Host '=== flutter build apk'
  $defines = @(python -I tool/fcm_defines.py (Join-Path $sec 'google-services.json') 2>$null)
  if ($LASTEXITCODE -ne 0 -or $defines.Count -ne 4) { Fail 'google-services.json illisible' }
  flutter build apk --release "--build-number=$number" "--dart-define=SARCADE_BUILD_NUMBER=$number" "--dart-define=SARCADE_BUILD=$build" @defines 2>&1 |
    Select-String -Pattern 'Built |error|Error|FAILURE|What went wrong' | ForEach-Object { $_.Line }
  $apk = 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path $apk)) { Fail 'APK non construit' }
  Copy-Item -Force $apk "$out\sarcade-android.apk"

  $files = @(
    (Entry 'windows' "$out\sarcade-windows-setup.exe" $version $build $canSign),
    (Entry 'android' "$out\sarcade-android.apk" $version $build $false),
    (Entry 'sources-app' $src $version $build $false)
  )
  $json = ConvertTo-Json -Depth 4 @($files)
  [IO.File]::WriteAllText("$out\app-files.json", $json, (New-Object Text.UTF8Encoding($false)))
  Write-Host "Fichiers : $out" -ForegroundColor Green
  Get-ChildItem $out | ForEach-Object { Write-Host ("  {0}  {1:N1} Mo" -f $_.Name, ($_.Length / 1MB)) }
}
finally {
  foreach ($v in 'SARCADE_KEYSTORE', 'SARCADE_KEYSTORE_PASSWORD', 'SARCADE_KEY_ALIAS', 'SARCADE_VERSION') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
  Set-Location $repo
  git -C $repo worktree remove --force $wt 2>$null
}
