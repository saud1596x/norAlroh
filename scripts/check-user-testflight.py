"""Authorize a source-pinned user-testing build, never a successful-test claim.

The ordinary reviewed-preview and App Store gates remain unchanged. This
separate channel is for the user's explicit request to test the unfinished
build on their iPhone after the unresolved checks were disclosed.
"""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SCOPES = ['ios', 'tools', 'content-sources', 'scripts', 'codemagic.yaml',
          'release/qcf-v2-manifest.json', 'release/config.json',
          'release/legal-content-accounts.json']
REQUEST = 'اريد تنشر ف تيست لايت انا بختبر التطبيق كامل'
UNVERIFIED = {'actualSimulatorAudio': 'FAILED_OR_TIMED_OUT',
              'currentFullReleaseSuite': 'NOT_PASSED',
              'currentDeviceAcceptance': 'USER_TO_TEST',
              'recognitionAndTajweedAccuracy': 'NOT_ESTABLISHED'}


def tracked_sources(root):
    raw = subprocess.check_output(['git', 'ls-files', '-z', '--', *SCOPES], cwd=root)
    return sorted(set(raw.decode('utf-8').rstrip('\0').split('\0')))


def validate(review, root, files):
    if review.get('schema') != 1 or review.get('channel') != 'TESTFLIGHT_USER_REVIEW':
        raise ValueError('Not a user-review authorization')
    if review.get('authorization') != REQUEST or review.get('status') != 'AUTHORIZED_FOR_USER_TESTING_ONLY':
        raise ValueError('Explicit user-testing request missing')
    if review.get('appleAppID') != '6819365625' or review.get('bundleID') != 'com.saud1596x.nooralruh':
        raise ValueError('Wrong application')
    if review.get('submitToAppStore') is not False or review.get('newExternalTesterInvitations') is not False:
        raise ValueError('Distribution exceeds user-testing scope')
    if review.get('unverified') != UNVERIFIED:
        raise ValueError('Unresolved verification must remain disclosed')
    hashes = review.get('sourceHashes', {})
    if not files or set(hashes) != set(files):
        raise ValueError('Pinned source inventory differs')
    for name in files:
        path = (root / name).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError('Invalid source path: ' + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != hashes[name]:
            raise ValueError('User-review source changed: ' + name)


def main():
    review = json.loads((ROOT / 'release/user-testflight-review.json').read_text(encoding='utf-8'))
    validate(review, ROOT, tracked_sources(ROOT))
    print('USER_TESTFLIGHT_SOURCE_PINNED; automated audio and full Release acceptance NOT PASSED; user device testing pending')


if __name__ == '__main__':
    main()
