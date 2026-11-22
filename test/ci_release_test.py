"""Exercise publishing without credentials or network calls."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = '1.0.8'
FILES = [f'OpenClash-{VERSION}-{abi}.apk' for abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64')]
FILES.append(f'SHA256SUMS-{VERSION}.txt')


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        build = (ROOT / 'build').resolve()
        build.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='release-test-', dir=build)
        self.folder = Path(self.temporary.name).resolve()
        self.folder.relative_to(build)
        self.addCleanup(self.temporary.cleanup)
        self.apks = self.folder / 'dist'
        self.apks.mkdir()
        checksums = []
        for name in FILES[:-1]:
            data = name.encode()
            (self.apks / name).write_bytes(data)
            checksums.append(f'{hashlib.sha256(data).hexdigest()}  {name}\n')
        (self.apks / FILES[-1]).write_bytes(''.join(checksums).encode('utf-8'))
        self.bin = self.folder / 'bin'
        self.bin.mkdir()
        self.log = self.folder / 'calls.log'
        self.summary = self.folder / 'summary.md'
        self.assets = self.folder / 'assets.txt'
        self.assets.write_bytes(('\n'.join(FILES) + '\n').encode('utf-8'))
        gh = self.bin / 'gh'
        gh.write_bytes('''#!/usr/bin/env bash
set -eu
echo "$*" >> "$MOCK_LOG"
if [[ "$1 $2" == 'release view' ]]; then
  if [[ "$*" == *'--json assets'* ]]; then cat "$MOCK_ASSETS"; exit 0; fi
  case "$MOCK_CASE" in
    published) echo false; exit 0 ;;
    draft) echo true; exit 0 ;;
    *) exit 1 ;;
  esac
fi
if [[ "$1" == api ]]; then
  if [[ "$2" == *'/git/ref/tags/'* ]]; then
    [[ "$MOCK_CASE" == draft || "$MOCK_CASE" == wrong_tag ]]; exit
  fi
  if [[ "$MOCK_CASE" == wrong_tag ]]; then echo different-commit; else echo test-commit; fi
  exit 0
fi
if [[ "$1 $2" == 'release upload' && "$MOCK_CASE" == upload_failure ]]; then exit 1; fi
exit 0
'''.encode('utf-8'))
        gh.chmod(0o755)

    def publish(self, case='new', signing='custom'):
        env = os.environ.copy()
        env.update(
            GH_REPO='example/project', GITHUB_SHA='test-commit',
            RELEASE_TAG=f'v{VERSION}', RELEASE_VERSION=VERSION,
            RELEASE_SIGNING=signing, RELEASE_PRERELEASE='false',
            APK_DIRECTORY=self.apks.as_posix(),
            GITHUB_STEP_SUMMARY=self.summary.as_posix(),
            MOCK_CASE=case, MOCK_LOG=self.log.as_posix(),
            MOCK_ASSETS=self.assets.as_posix(), MOCK_BIN=self.bin.as_posix(),
            PUBLISH_SCRIPT=(ROOT / 'scripts/publish-android.sh').as_posix(),
        )
        bash = env.get('BASH_FOR_TESTS') or shutil.which('bash')
        self.assertIsNotNone(bash, 'Bash is required for publisher tests')
        command = 'export PATH="$MOCK_BIN:$PATH"; bash "$PUBLISH_SCRIPT"'
        if os.name == 'nt':
            command = 'export PATH="$(cygpath -u "$MOCK_BIN"):$PATH"; bash "$(cygpath -u "$PUBLISH_SCRIPT")"'
        result = subprocess.run([bash, '-c', command], env=env, capture_output=True, text=True, timeout=15)
        calls = self.log.read_text(encoding='utf-8') if self.log.exists() else ''
        return result, calls

    def test_publishes_all_assets_before_showing_release(self):
        result, calls = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in FILES:
            self.assertIn(name, calls)
        self.assertLess(calls.index('release upload'), calls.index('--draft=false'))
        self.assertIn('Published', self.summary.read_text())

    def test_published_version_is_not_overwritten(self):
        result, calls = self.publish('published')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('release create', calls)
        self.assertNotIn('release upload', calls)

    def test_failed_draft_resumes_without_recreating_release(self):
        result, calls = self.publish('draft')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('release create', calls)
        self.assertIn('--clobber', calls)
        self.assertIn('--draft=false', calls)

    def test_failed_upload_keeps_release_hidden(self):
        result, calls = self.publish('upload_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('--draft=false', calls)

    def test_tag_cannot_publish_a_different_commit(self):
        result, calls = self.publish('wrong_tag')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('release upload', calls)

    def test_checksum_failure_does_not_modify_github(self):
        (self.apks / FILES[0]).write_bytes(b'corrupted')
        result, calls = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, '')

    def test_debug_signature_is_disclosed_in_release_notes(self):
        result, _ = self.publish(signing='debug')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('temporary Android debug certificate', (self.apks / 'release-notes.md').read_text())


if __name__ == '__main__':
    unittest.main()
