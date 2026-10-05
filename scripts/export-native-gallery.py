"""Export actual XCUITest PNG attachments. Never renders designs or substitutes placeholder images."""
import datetime
import html
import json
import platform
import re
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULT = ROOT / 'release/native-ui.xcresult'
OUTPUT = ROOT / 'release/native-screens'


def attachment_records(value):
    if isinstance(value, dict):
        if isinstance(value.get('exportedFileName'), str):
            yield value
        for child in value.values():
            yield from attachment_records(child)
    elif isinstance(value, list):
        for child in value:
            yield from attachment_records(child)


def main():
    if platform.system() != 'Darwin' or not RESULT.is_dir():
        raise SystemExit('Requires an actual Xcode UI test result bundle on macOS; no screenshots created.')
    if OUTPUT.exists():
        raise SystemExit('Archive or remove the previous native-screens directory before a fresh capture.')
    OUTPUT.mkdir()
    exported = OUTPUT / 'attachments'
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(RESULT),
                    '--output-path', str(exported)], check=True)
    inventory = json.loads((ROOT / 'release/screen-inventory.json').read_text())['screens']
    expected = {row['id']: row['title'] for row in inventory}
    records = []
    for manifest in exported.rglob('manifest.json'):
        for attachment in attachment_records(json.loads(manifest.read_text())):
            filename = attachment['exportedFileName']
            candidates = [p for p in exported.rglob('*.png') if p.name == Path(filename).name]
            if len(candidates) != 1:
                continue
            path = candidates[0]
            if not path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
                continue
            label = attachment.get('suggestedHumanReadableName', '')
            match = re.match(r'^(\d{2}-[a-z-]+)', Path(label).name)
            identifier = match.group(1) if match else None
            records.append({'id': identifier, 'title': expected.get(identifier, label or path.name),
                            'file': str(path.relative_to(OUTPUT))})
    if not records:
        raise SystemExit('No named PNG screenshots exported. Inspect the Xcode attachment manifest; do not claim a gallery.')
    recorded = {row['id'] for row in records}
    missing = [key for key in expected if key not in recorded]
    report = {'status': 'ALL_INVENTORY_CAPTURES_EXPORTED' if not missing else 'INCOMPLETE_CAPTURE',
              'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'source': 'Actual XCUITest attachments from native-ui.xcresult',
              'screenshots': records, 'missingScreenIDs': missing,
              'note': 'Screenshots do not certify correctness or device testing. Simulator MP4 has no microphone audio.'}
    (OUTPUT / 'capture-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    ordered = sorted(records, key=lambda row: row['id'] or 'zz')
    cards = ''.join('<figure><img loading="lazy" src="' + html.escape(row['file'], quote=True) +
                    '" alt="' + html.escape(row['title'], quote=True) + '"><figcaption>' +
                    html.escape(row['title']) + '</figcaption></figure>' for row in ordered)
    page = '''<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>نور الروح — شاشات iOS</title>
<style>body{font-family:system-ui;background:#f1e2c6;color:#2d2117;margin:0;padding:24px}
main{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:24px}
figure{margin:0;background:#fff7e9;border-radius:20px;padding:16px}img{width:100%;height:auto;border-radius:12px}
figcaption{margin-top:12px;font-weight:600}</style><h1>نور الروح</h1>
<p>لقطات من التطبيق الأصلي على محاكي iPhone. حالات الاختبار تظهر كما التُقطت، ويلزم فحص جهاز فعلي.</p>'''
    page += '<p>اللقطات الناقصة: ' + html.escape('، '.join(missing) or 'لا يوجد') + '</p><main>' + cards + '</main></html>'
    (OUTPUT / 'index.html').write_text(page)
    with zipfile.ZipFile(ROOT / 'release/native-screens.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in OUTPUT.rglob('*'):
            if path.is_file():
                archive.write(path, 'native-screens/' + str(path.relative_to(OUTPUT)))
    print(json.dumps({'screenshots': len(records), 'status': report['status'], 'missing': missing}, ensure_ascii=False))
    return 1 if missing else 0


if __name__ == '__main__':
    raise SystemExit(main())
