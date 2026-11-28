#!/usr/bin/env bash
set -euo pipefail

directory=${1:?Missing APK directory}
version=${2:?Missing release version}
apksigner=${APKSIGNER:-apksigner}
# SHA-256 fingerprint of the certificate used to sign the official v1.1.0 APKs.
readonly release_certificate=34a4dab9f5988c324bcd65b48b54dea68182c95a80d08397ae5d29a89cbbd50a

command -v "$apksigner" >/dev/null || {
  echo '::error::Android SDK apksigner is required to verify release APKs.'
  exit 1
}

for abi in arm64-v8a armeabi-v7a x86_64; do
  apk="$directory/OpenClash-$version-$abi.apk"
  if [[ ! -s "$apk" ]] || ! result=$("$apksigner" verify --print-certs "$apk"); then
    echo "::error::APK signature verification failed: $apk"
    exit 1
  fi
  mapfile -t signers < <(sed -nE 's/^Signer #[0-9]+ certificate SHA-256 digest: ([[:xdigit:]]{64})[[:space:]]*$/\1/p' <<< "$result")
  if [[ ${#signers[@]} -ne 1 || "${signers[0],,}" != "$release_certificate" ]]; then
    echo "::error::APK must have exactly one signer matching the official release certificate: $apk"
    exit 1
  fi
  echo "Verified official Android signature: $apk"
done
