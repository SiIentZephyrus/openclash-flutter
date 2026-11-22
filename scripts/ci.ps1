param(
    [switch]$BuildOnly,
    [switch]$Prerelease,
    [string]$Ref = 'main',
    [string]$Repository = 'SiIentZephyrus/openclash-flutter'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'Install GitHub CLI (https://cli.github.com), then run gh auth login. You can also use Actions > Android APK > Run workflow on GitHub.'
}

$publish = (-not $BuildOnly.IsPresent).ToString().ToLowerInvariant()
$preview = $Prerelease.IsPresent.ToString().ToLowerInvariant()
& gh workflow run android.yml --repo $Repository --ref $Ref -f "publish=$publish" -f "prerelease=$preview"
if ($LASTEXITCODE -ne 0) { throw 'Failed to trigger Android APK workflow.' }
Write-Host "Triggered Android APK ($Ref, publish=$publish)."
Write-Host "Runs: https://github.com/$Repository/actions/workflows/android.yml"
Write-Host "Releases: https://github.com/$Repository/releases"
