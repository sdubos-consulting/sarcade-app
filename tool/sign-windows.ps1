# Signature Windows sur l'i9 avec Azure Artifact Signing (ex-Trusted Signing),
# à la place de GitHub Actions (carte « Windows, installeur bloqué par
# Defender : signer le code », décision du porteur du 9 novembre 2026).
# Appelé par tool\build-downloads.ps1 pour sarcade_app.exe puis l'installeur.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\sign-windows.ps1 -Files <fichier.exe>
#
# Réglages rangés par le porteur avec tool\azure-signing-setup.ps1, jamais
# affichés : C:\dev\secrets\windows\azure-signing.json (annuaire, application,
# adresse, compte, profil) et azure-client-secret.dpapi (secret de
# l'application, chiffré pour la session Windows du porteur). Outils :
# signtool du SDK Windows et « Trusted Signing Client Tools » (winget
# Microsoft.Azure.TrustedSigningClientTools).
param([Parameter(Mandatory = $true)][string[]]$Files)
$ErrorActionPreference = 'Stop'
$sec = 'C:\dev\secrets\windows'
function Fail([string]$m) { Write-Host "ÉCHEC signature : $m" -ForegroundColor Red; exit 1 }

if (-not (Test-Path "$sec\azure-signing.json") -or -not (Test-Path "$sec\azure-client-secret.dpapi")) { Fail "réglages absents dans $sec (tool\azure-signing-setup.ps1)" }
$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like '*\x64\*' } | Sort-Object FullName | Select-Object -Last 1
if (-not $signtool) { Fail 'signtool.exe absent (SDK Windows)' }
$dlib = Get-ChildItem "$env:LOCALAPPDATA\Microsoft", $env:ProgramFiles, "${env:ProgramFiles(x86)}" -Recurse -Filter Azure.CodeSigning.Dlib.dll -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like '*\x64\*' -or $_.FullName -notlike '*\x86\*' } | Select-Object -First 1
if (-not $dlib) { Fail 'Azure.CodeSigning.Dlib.dll absent (winget install -e --id Microsoft.Azure.TrustedSigningClientTools)' }

$cfg = [IO.File]::ReadAllText("$sec\azure-signing.json") | ConvertFrom-Json
foreach ($k in 'tenantId', 'clientId', 'endpoint', 'account', 'profile') { if (-not $cfg.$k) { Fail "valeur « $k » absente de azure-signing.json" } }
$meta = Join-Path $env:TEMP "sarcade-signing-$PID.json"
try {
  $secure = [IO.File]::ReadAllText("$sec\azure-client-secret.dpapi").Trim() | ConvertTo-SecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $env:AZURE_CLIENT_SECRET = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  $env:AZURE_TENANT_ID = $cfg.tenantId
  $env:AZURE_CLIENT_ID = $cfg.clientId
  # Seule l'application (variables ci-dessus) : pas de connexion interactive.
  $m = [ordered]@{ Endpoint = $cfg.endpoint; CodeSigningAccountName = $cfg.account; CertificateProfileName = $cfg.profile
                   ExcludeCredentials = @('ManagedIdentityCredential', 'WorkloadIdentityCredential', 'SharedTokenCacheCredential',
                     'VisualStudioCredential', 'VisualStudioCodeCredential', 'AzureCliCredential', 'AzurePowerShellCredential',
                     'AzureDeveloperCliCredential', 'InteractiveBrowserCredential') }
  [IO.File]::WriteAllText($meta, (ConvertTo-Json $m), (New-Object Text.UTF8Encoding($false)))
  foreach ($f in $Files) {
    if (-not (Test-Path $f)) { Fail "fichier absent : $f" }
    & $signtool.FullName sign /fd SHA256 /tr 'http://timestamp.acs.microsoft.com' /td SHA256 /dlib $dlib.FullName /dmdf $meta $f | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "signtool sign $f (code $LASTEXITCODE)" }
    & $signtool.FullName verify /pa $f | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "signature non valide : $f" }
    Write-Host "Signé : $f" -ForegroundColor Green
  }
}
finally {
  foreach ($v in 'AZURE_CLIENT_SECRET', 'AZURE_TENANT_ID', 'AZURE_CLIENT_ID') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
  Remove-Item $meta -ErrorAction SilentlyContinue
}
exit 0
