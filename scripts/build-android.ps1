param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    if (-not $SkipBuild) {
        & flutter build apk --release --split-per-abi
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    }

    $versionMatch = [regex]::Match((Get-Content -LiteralPath 'pubspec.yaml' -Raw), '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?)')
    if (-not $versionMatch.Success) { throw 'Cannot read app version from pubspec.yaml.' }
    $appVersion = $versionMatch.Groups[1].Value
    New-Item -ItemType Directory -Path 'dist' -Force | Out-Null
    $checksums = @()
    $packages = foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
        $sourceApk = Join-Path 'build/app/outputs/flutter-apk' "app-$abi-release.apk"
        if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) { throw "Missing APK: $sourceApk" }
        $fileName = "OpenClash-$appVersion-$abi.apk"
        $targetApk = Join-Path 'dist' $fileName
        Copy-Item -LiteralPath $sourceApk -Destination $targetApk
        $digest = (Get-FileHash -LiteralPath $targetApk -Algorithm SHA256).Hash.ToLowerInvariant()
        $checksums += "$digest  $fileName"
        [pscustomobject]@{ ABI = $abi; SizeMiB = [math]::Round((Get-Item -LiteralPath $targetApk).Length / 1MB, 2); APK = $targetApk }
    }
    Set-Content -LiteralPath (Join-Path 'dist' "SHA256SUMS-$appVersion.txt") -Value $checksums -Encoding utf8
    $packages | Format-Table -AutoSize
} finally {
    Pop-Location
}
