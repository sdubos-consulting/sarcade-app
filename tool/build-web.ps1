# Client web construit sur l'i9, comme le faisait la CI GitHub (suspendue
# depuis le 6 novembre 2026) : worktree neuf de gitlab/main, build web,
# sarcade_build.json, nom du code daté par le build (tool/version_web.py),
# archive sarcade-web.tar.gz pour le serveur (SARCADE_WEB=local du
# Dockerfile de sarcade-server). Windows PowerShell 5.1 ; relançable.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\build-web.ps1
#
# Résultat : C:\dev\sarcade\publications\web\sarcade-web-<commit>.tar.gz
# Numéro de build : celui de la dernière version Android publiée depuis l'i9
# (C:\dev\sarcade\publications\android), pour des numéros alignés.
$ErrorActionPreference = 'Continue'
$repo = 'C:\dev\sarcade\sarcade-app'
$out  = 'C:\dev\sarcade\publications\web'
$wt   = "C:\dev\sarcade\wt\web-build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

function Fail([string]$msg) { Write-Host "ÉCHEC : $msg" -ForegroundColor Red; throw $msg }

New-Item -ItemType Directory -Force $out | Out-Null
try {
  Get-ChildItem 'C:\dev\sarcade\wt' -Directory -Filter 'web-build-*' -ErrorAction SilentlyContinue | ForEach-Object {
    git -C $repo worktree remove --force $_.FullName 2>$null
  }
  git -C $repo worktree prune
  git -C $repo fetch -q gitlab
  if ($LASTEXITCODE -ne 0) { Fail 'git fetch gitlab' }
  $sha = (git -C $repo rev-parse --short gitlab/main).Trim()
  $build = "main@$sha"
  $number = 0
  Get-ChildItem 'C:\dev\sarcade\publications\android' -Filter 'sarcade-*.aab' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^sarcade-(\d+)-') { $number = [math]::Max($number, [int]$Matches[1]) }
  }
  Write-Host "=== gitlab/main = $sha, build $number"
  git -C $repo worktree add -q --detach $wt gitlab/main
  if ($LASTEXITCODE -ne 0) { Fail "worktree $wt" }
  Set-Location $wt

  flutter create --platforms=web --org org.sarcade --no-pub . | Out-Null
  Remove-Item -Force -ErrorAction SilentlyContinue 'test\widget_test.dart'
  python tool/patch_web.py
  if ($LASTEXITCODE -ne 0) { Fail 'patch_web.py' }
  flutter pub get | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get' }

  Write-Host '=== flutter build web'
  flutter build web --release --no-web-resources-cdn "--dart-define=SARCADE_BUILD_NUMBER=$number" "--dart-define=SARCADE_BUILD=$build" 2>&1 |
    Select-String -Pattern 'Built |error|Error|FAILED' | ForEach-Object { $_.Line }
  if (-not (Test-Path 'build\web\main.dart.js')) { Fail 'build web' }

  # Build servi à côté du client : les clients ouverts proposent « Mettre à jour ».
  $v = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
  [IO.File]::WriteAllText("$wt\build\web\sarcade_build.json", "{`"build`":`"$build`",`"version`":`"$v+$number`"}`n", (New-Object Text.UTF8Encoding($false)))
  python tool/version_web.py build/web $build
  if ($LASTEXITCODE -ne 0) { Fail 'version_web.py' }

  $tar = Join-Path $out "sarcade-web-$sha.tar.gz"
  tar -czf $tar -C build/web .
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tar)) { Fail 'archive' }
  Write-Host "Archive : $tar ($([math]::Round((Get-Item $tar).Length / 1MB, 1)) Mo)" -ForegroundColor Green
}
finally {
  Set-Location $repo
  git -C $repo worktree remove --force $wt 2>$null
}
