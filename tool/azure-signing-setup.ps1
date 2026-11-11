# Range les réglages de la signature Windows Azure sur l'i9 (lancé une fois
# par le porteur, dans un PowerShell normal) ; rien n'est affiché. Le secret de
# l'application Entra « sarcade-github-signing » est collé depuis KeePass et
# chiffré pour la session Windows du porteur (DPAPI) : seul ce compte, sur
# cet i9, peut le relire (tool\sign-windows.ps1). Relançable : remplace les
# réglages.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\sarcade\sarcade-app\tool\azure-signing-setup.ps1
$ErrorActionPreference = 'Stop'
$sec = 'C:\dev\secrets\windows'
New-Item -ItemType Directory -Force $sec | Out-Null
$tenant = (Read-Host 'Directory (tenant) ID (portail Azure, Microsoft Entra ID, page Overview)').Trim()
$client = (Read-Host 'Application (client) ID de sarcade-github-signing (App registrations)').Trim()
$profileName = (Read-Host 'Nom du profil de certificat (Artifact Signing, Certificate profiles)').Trim()
$secret = Read-Host 'Secret client (coller depuis KeePass, rien ne s''affiche)' -AsSecureString
if ($tenant -notmatch '^[0-9a-fA-F-]{36}$' -or $client -notmatch '^[0-9a-fA-F-]{36}$') { throw 'les deux ID doivent être des GUID de 36 caractères' }
if (-not $profileName) { throw 'nom de profil vide' }
if ($secret.Length -lt 20) { throw 'secret trop court : vérifier le collage' }
$cfg = [ordered]@{ tenantId = $tenant; clientId = $client; endpoint = 'https://neu.codesigning.azure.net'; account = 'sdubossigning'; profile = $profileName }
[IO.File]::WriteAllText("$sec\azure-signing.json", (ConvertTo-Json $cfg), (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText("$sec\azure-client-secret.dpapi", ($secret | ConvertFrom-SecureString), (New-Object Text.UTF8Encoding($false)))
Write-Host "Réglages rangés dans $sec (azure-signing.json, azure-client-secret.dpapi)." -ForegroundColor Green
