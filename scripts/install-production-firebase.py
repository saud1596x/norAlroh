"""Install the real Firebase plist from Codemagic's protected environment.
Never print configuration values or silently build without account support.
"""
import base64
import importlib.util
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    encoded = os.environ.get('NOOR_FIREBASE_IOS_PLIST_BASE64', '')
    if not encoded:
        raise SystemExit('Set NOOR_FIREBASE_IOS_PLIST_BASE64 in protected noor_release configuration using the refreshed Firebase iOS plist.')
    try:
        payload = base64.b64decode(encoded, validate=True)
    except ValueError:
        raise SystemExit('Firebase build configuration is not valid base64.')
    spec = importlib.util.spec_from_file_location('noor_firebase', ROOT / 'scripts/configure-firebase.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / 'GoogleService-Info.plist'
        source.write_bytes(payload)
        source.chmod(0o600)
        module.install(source)
    print('PRODUCTION_FIREBASE_CONFIGURATION_INSTALLED; providers and actual sign-in still require verification')

if __name__ == '__main__':
    main()
