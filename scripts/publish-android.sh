#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?Missing repository}"
: "${GITHUB_SHA:?Missing build commit}"
: "${RELEASE_TAG:?Missing release tag}"
: "${RELEASE_VERSION:?Missing release version}"

cd "${APK_DIRECTORY:-dist}"
files=(
  "OpenClash-$RELEASE_VERSION-arm64-v8a.apk"
  "OpenClash-$RELEASE_VERSION-armeabi-v7a.apk"
  "OpenClash-$RELEASE_VERSION-x86_64.apk"
  "SHA256SUMS-$RELEASE_VERSION.txt"
)
for file in "${files[@]}"; do
  [[ -s "$file" ]] || { echo "::error::Missing or empty release asset: $file"; exit 1; }
done
sha256sum --check "SHA256SUMS-$RELEASE_VERSION.txt"
release_url="https://github.com/$GH_REPO/releases/tag/$RELEASE_TAG"

# Published versions are immutable. Re-running CI with the same version should
# succeed without replacing signed APKs or moving an existing release tag.
existing_draft=$(gh release view "$RELEASE_TAG" --json isDraft --jq .isDraft 2>/dev/null || true)
if [[ "$existing_draft" == false ]]; then
  echo "::notice::Release $RELEASE_TAG already exists; bump pubspec.yaml to publish another version."
  echo "### Existing release: [$RELEASE_TAG]($release_url)" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

if gh api "repos/$GH_REPO/git/ref/tags/$RELEASE_TAG" >/dev/null 2>&1; then
  tag_commit=$(gh api "repos/$GH_REPO/commits/$RELEASE_TAG" --jq .sha)
  [[ "$tag_commit" == "$GITHUB_SHA" ]] || { echo '::error::Existing tag points to a different commit.'; exit 1; }
fi

cat > release-notes.md <<EOF
Android APKs built from commit $GITHUB_SHA.

- arm64-v8a: 64-bit ARM phones (recommended for most devices)
- armeabi-v7a: 32-bit ARM devices
- x86_64: 64-bit x86 devices / emulators

Install one APK matching your device. SHA-256 checksums are included.
EOF
if [[ "${RELEASE_SIGNING:-debug}" != custom ]]; then
  cat >> release-notes.md <<'EOF'

Signing: this build uses the CI runner's temporary Android debug certificate.
Upgrading from a differently signed build requires uninstalling it first (local
settings will be removed). Configure the Android signing secrets before the next
release to use a fixed certificate for future upgrades.
EOF
fi

if [[ "$existing_draft" != true ]]; then
  gh release create "$RELEASE_TAG" --target "$GITHUB_SHA" \
    --title "OpenClash $RELEASE_VERSION" --notes-file release-notes.md --draft
else
  # Resume a failed draft upload for the exact same build commit.
  gh release edit "$RELEASE_TAG" --notes-file release-notes.md
fi
gh release upload "$RELEASE_TAG" "${files[@]}" --clobber

args=(--draft=false)
if [[ "${RELEASE_PRERELEASE:-false}" == true ]]; then args+=(--prerelease); fi
gh release edit "$RELEASE_TAG" "${args[@]}"

# Confirm that the public release really contains every expected download.
assets=$(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name')
for file in "${files[@]}"; do
  grep -Fxq "$file" <<< "$assets" || { echo "::error::Release asset not visible: $file"; exit 1; }
done
echo "### Published [$RELEASE_TAG]($release_url)" >> "$GITHUB_STEP_SUMMARY"
echo "Release downloads: $release_url"
