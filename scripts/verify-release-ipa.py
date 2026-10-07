"""Verify the complete distribution payload; this does not certify device behavior.
Xcode performs signing. This gate prevents uploading a local-only or incomplete app.
"""
import glob
import importlib.util
import json
import plistlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'com.saud1596x.nooralruh'
EXTENSIONS = {
    BUNDLE + '.widgets': 'com.apple.widgetkit-extension',
    BUNDLE + '.focus-monitor': 'com.apple.deviceactivity.monitor-extension',
    BUNDLE + '.focus-shield': 'com.apple.ManagedSettingsUI.shield-configuration-service',
    BUNDLE + '.focus-action': 'com.apple.ManagedSettings.shield-action-service',
}

def verify(path):
    spec = importlib.util.spec_from_file_location('noor_firebase', ROOT / 'scripts/configure-firebase.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with zipfile.ZipFile(path) as ipa:
        names = set(ipa.namelist())
        roots = [n.removesuffix('Info.plist') for n in names
                 if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(roots) != 1:
            raise ValueError('Expected one top-level app bundle')
        root = roots[0]
        info = plistlib.loads(ipa.read(root + 'Info.plist'))
        if info.get('CFBundleIdentifier') != BUNDLE:
            raise ValueError('Wrong production app identifier')
        version = (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion'))
        if not all(isinstance(v, str) and v for v in version):
            raise ValueError('Missing release version/build')
        configuration = plistlib.loads(ipa.read(root + 'GoogleService-Info.plist'))
        module.validate(configuration)
        legal = json.loads(ipa.read(root + 'app-legal.json'))
        if legal.get('accountMode') != 'firebase-opt-in':
            raise ValueError('Bundled privacy policy still describes local-only use; review and publish the actual account policy first')
        if legal.get('contact', {}).get('supportEmail') != 'noralrohsupport@gmail.com':
            raise ValueError('Bundled support email differs from the approved public contact')
        if root + 'embedded.mobileprovision' not in names:
            raise ValueError('Missing app distribution profile')
        extension_infos = [n for n in names if n.startswith(root + 'PlugIns/')
                           and n.count('/') == 4 and n.endswith('.appex/Info.plist')]
        found = set()
        for name in extension_infos:
            extension = plistlib.loads(ipa.read(name))
            identifier = extension.get('CFBundleIdentifier')
            if identifier not in EXTENSIONS or identifier in found:
                raise ValueError('Unexpected or duplicate extension')
            found.add(identifier)
            if extension.get('NSExtension', {}).get('NSExtensionPointIdentifier') != EXTENSIONS[identifier]:
                raise ValueError('Incorrect extension registration: ' + identifier)
            if (extension.get('CFBundleShortVersionString'), extension.get('CFBundleVersion')) != version:
                raise ValueError('Extension version/build differs from app: ' + identifier)
            if name.removesuffix('Info.plist') + 'embedded.mobileprovision' not in names:
                raise ValueError('Missing extension distribution profile: ' + identifier)
        if found != set(EXTENSIONS):
            raise ValueError('Missing required extensions: ' + ', '.join(sorted(set(EXTENSIONS) - found)))
    return {'version': version[0], 'build': version[1], 'extensions': sorted(found),
            'accountConfigurationIncluded': True, 'deviceTested': False}

def main():
    paths = glob.glob(str(ROOT / 'build/ios/ipa/*.ipa'))
    if len(paths) != 1:
        raise SystemExit('Expected exactly one signed IPA')
    try:
        report = verify(paths[0])
    except (ValueError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit('RELEASE_PAYLOAD_BLOCKED: ' + str(error))
    (ROOT / 'release/release-payload-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('RELEASE_PAYLOAD_VERIFIED: account configuration and four extensions; not a device acceptance result')

if __name__ == '__main__':
    main()
