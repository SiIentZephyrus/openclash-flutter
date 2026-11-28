#!/usr/bin/env bash
set -euo pipefail

: "${KEYSTORE_BASE64:?Missing ANDROID_KEYSTORE_BASE64}"
: "${KEYSTORE_PASSWORD:?Missing ANDROID_KEYSTORE_PASSWORD}"
: "${KEY_ALIAS:?Missing ANDROID_KEY_ALIAS}"
: "${KEY_PASSWORD:?Missing ANDROID_KEY_PASSWORD}"
: "${RUNNER_TEMP:?Missing runner temporary directory}"

umask 077
printf '%s' "$KEYSTORE_BASE64" | base64 --decode > "$RUNNER_TEMP/android-release.keystore"
python3 - <<'PY'
import os
from pathlib import Path


def escape(value):
    encoded = value.encode('utf-16-be')
    return ''.join('\\u%04x' % int.from_bytes(encoded[i:i+2], 'big')
                   for i in range(0, len(encoded), 2))


values = {
    'storeFile': os.environ['RUNNER_TEMP'] + '/android-release.keystore',
    'storePassword': os.environ['KEYSTORE_PASSWORD'],
    'keyAlias': os.environ['KEY_ALIAS'],
    'keyPassword': os.environ['KEY_PASSWORD'],
}
Path('android/key.properties').write_text(''.join(
    f'{key}={escape(value)}\n' for key, value in values.items()),
    encoding='ascii',
)
PY
