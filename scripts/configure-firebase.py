"""Validate the existing project's downloaded iOS configuration; never invent IDs.
This installs files only. It does not enable providers, deploy rules, or certify sign-in.
"""
import argparse
import plistlib
from pathlib import Path
import re
import shutil

PROJECT = 'noor-alruh'
BUNDLE = 'com.saud1596x.nooralruh'
APP = '1:149675464789:ios:32a19ae8e5a62439561cdc'
ROOT = Path(__file__).resolve().parents[1]

def validate(config):
    for field, expected in [('PROJECT_ID', PROJECT), ('BUNDLE_ID', BUNDLE), ('GOOGLE_APP_ID', APP)]:
        if config.get(field) != expected:
            raise ValueError(f'{field}: configuration does not belong to the registered Noor iOS app')
    client = config.get('CLIENT_ID', '')
    reversed_client = config.get('REVERSED_CLIENT_ID', '')
    if not re.fullmatch(r'[A-Za-z0-9-]+\.apps\.googleusercontent\.com', client):
        raise ValueError('CLIENT_ID missing/invalid; enable Google in Firebase Authentication and download the refreshed plist')
    if reversed_client != '.'.join(reversed(client.split('.'))):
        raise ValueError('REVERSED_CLIENT_ID does not match CLIENT_ID')
    if not isinstance(config.get('API_KEY'), str) or not config['API_KEY']:
        raise ValueError('API_KEY missing; download the original configuration')
    return reversed_client

def install(source, root=ROOT):
    config = plistlib.loads(source.read_bytes())
    scheme = validate(config)
    info_path = root / 'ios/Athar/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    types = info.setdefault('CFBundleURLTypes', [])
    existing = {s for entry in types for s in entry.get('CFBundleURLSchemes', [])}
    if scheme not in existing:
        types.append({'CFBundleURLSchemes': [scheme]})
    # Preserve the pre-configuration metadata so the operation is reversible.
    backup = info_path.with_suffix('.plist.before-firebase')
    if not backup.exists():
        shutil.copy2(info_path, backup)
    temporary = info_path.with_suffix('.plist.pending')
    temporary.write_bytes(plistlib.dumps(info, sort_keys=False))
    destination = root / 'ios/Athar/GoogleService-Info.plist'
    if source.resolve() != destination.resolve():
        shutil.copy2(source, destination)
    temporary.replace(info_path)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plist', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        validate(plistlib.loads(args.plist.read_bytes()))
        if not args.check:
            install(args.plist)
        print('CONFIG_VALIDATED' if args.check else 'CONFIG_INSTALLED; AUTHENTICATION_AND_SYNC_NOT_TESTED')
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        parser.exit(1, str(error) + '\n')
