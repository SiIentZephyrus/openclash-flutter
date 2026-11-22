param(
    [string]$KeystorePath,
    [string]$KeyAlias,
    [securestring]$StorePassword,
    [securestring]$KeyPassword,
    [switch]$UseCurrentDebugKey,
    [string]$Repository = 'SiIentZephyrus/openclash-flutter'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'Install GitHub CLI (https://cli.github.com), then run gh auth login.'
}

if ($UseCurrentDebugKey) {
    $KeystorePath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.android/debug.keystore'
    $KeyAlias = 'androiddebugkey'
    $StorePassword = ConvertTo-SecureString 'android' -AsPlainText -Force
    $KeyPassword = $StorePassword
}
if (-not $KeystorePath -or -not (Test-Path -LiteralPath $KeystorePath -PathType Leaf)) {
    throw 'Provide -KeystorePath pointing to your existing Android keystore, or -UseCurrentDebugKey to reuse the local preview signing certificate.'
}
if (-not $KeyAlias) { throw 'Provide -KeyAlias.' }
if (-not $StorePassword) { $StorePassword = Read-Host 'Keystore password' -AsSecureString }
if (-not $KeyPassword) { $KeyPassword = $StorePassword }

# gh reads each value from stdin and encrypts it before uploading. Never place
# keystore values or passwords in command arguments, files, or console output.
function Set-RepositorySecret([string]$Name, [string]$Value) {
    $Value | & gh secret set $Name --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Failed to configure $Name. Run gh auth login and check repository access." }
}

Set-RepositorySecret 'ANDROID_KEYSTORE_BASE64' ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $KeystorePath).Path)))
Set-RepositorySecret 'ANDROID_KEYSTORE_PASSWORD' ([System.Net.NetworkCredential]::new('', $StorePassword).Password)
Set-RepositorySecret 'ANDROID_KEY_ALIAS' $KeyAlias
Set-RepositorySecret 'ANDROID_KEY_PASSWORD' ([System.Net.NetworkCredential]::new('', $KeyPassword).Password)
Write-Host "Configured the four Android signing secrets in $Repository. Keep a backup of the keystore."
