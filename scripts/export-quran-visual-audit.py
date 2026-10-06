"""Export production iOS canvas attachments; image export is not visual approval."""
import argparse
import datetime
import hashlib
import html
import json
import platform
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def records(value):
    if isinstance(value, dict):
        if 'exportedFileName' in value:
            yield value
        for child in value.values():
            yield from records(child)
    elif isinstance(value, list):
        for child in value:
            yield from records(child)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--result', type=Path, default=ROOT / 'release/quran-visual.xcresult')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or not args.result.is_dir():
        raise SystemExit('Actual Xcode result bundle required; no images generated.')
    output = ROOT / 'release/quran-visual-audit'
    if output.exists():
        raise SystemExit('Archive previous audit before exporting a fresh result.')
    raw = output / 'raw'
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(args.result),
                    '--output-path', str(raw)], check=True)
    exported = []
    for manifest in raw.rglob('manifest.json'):
        for item in records(json.loads(manifest.read_text())):
            match = re.match(r'^mushaf-page-(\d{3})-(phone-light|tablet-light|phone-dark)',
                             item.get('suggestedHumanReadableName', ''))
            if not match:
                continue
            page, mode = int(match[1]), match[2]
            candidates = list(raw.rglob(Path(item['exportedFileName']).name))
            if len(candidates) != 1 or not candidates[0].read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
                raise SystemExit('Missing or invalid native page attachment')
            target = output / f'page-{page:03}-{mode}.png'
            if target.exists():
                raise SystemExit('Duplicate native page attachment')
            shutil.copyfile(candidates[0], target)
            exported.append({'page': page, 'mode': mode, 'file': target.name,
                             'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                             'visualReview': 'PENDING'})
    pages = {x['page'] for x in exported if x['mode'] == 'phone-light'}
    complete = pages == set(range(1, 605))
    report = {'status': 'CAPTURED_NOT_VISUALLY_APPROVED' if complete else 'INCOMPLETE_CAPTURE',
              'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'source': 'Production MushafLineCanvas / UIKit / CoreText on iOS simulator',
              'scope': 'Native page canvas; excludes app navigation and scroll viewport.',
              'religiousApproval': 'NOT_CERTIFIED', 'pagesVisuallyReviewed': [],
              'all604PhonePagesCaptured': complete, 'images': sorted(exported, key=lambda x: (x['page'], x['mode']))}
    (output / 'audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    cards = ''.join(f'<figure><img loading="lazy" src="{html.escape(x["file"])}" alt="صفحة {x["page"]}"><figcaption>صفحة {x["page"]} · {x["mode"]} · لم تُعتمد بصريًا</figcaption></figure>' for x in report['images'])
    (output / 'index.html').write_text('<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><title>تدقيق المصحف</title><style>body{font-family:system-ui;background:#eee;padding:20px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(350px,1fr));gap:20px}figure{margin:0;background:white;padding:8px}img{width:100%;height:auto}figcaption{padding:10px}</style><h1>صور تدقيق المصحف</h1><p>رسم أصلي من iOS. توفر الصور لا يعني اعتماد صحة جميع الصفحات. الصور لا تشمل قوائم التطبيق.</p><main>' + cards + '</main></html>')
    shutil.rmtree(raw)
    print(json.dumps({'pages': len(pages), 'images': len(exported), 'status': report['status']}))
    return 0 if complete else 1

if __name__ == '__main__':
    raise SystemExit(main())
