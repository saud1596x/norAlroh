"""Generate consistent offline legal content and unpublished static support pages."""
import argparse, hashlib, html, json, re, sys
from pathlib import Path
from urllib.parse import quote, urlparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true', help='Fail if generated files differ; do not rewrite them.')
args = parser.parse_args()
config = json.loads((ROOT / 'release/config.json').read_text())
content = json.loads((ROOT / 'release/legal-content.json').read_text())
if config.get('userAccountMode', 'local-only') != 'local-only':
    raise SystemExit('Account-backed authentication and server deletion are not implemented. Update privacy and implementation before enabling accounts.')
email = config.get('supportEmail')
if email is not None and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email):
    raise SystemExit('Set supportEmail to a valid address or null; do not publish a placeholder.')
for key in ['privacyURL', 'supportURL', 'termsURL']:
    value = config.get(key)
    if value is not None:
        parsed = urlparse(value)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or any(c.isspace() for c in value):
            raise SystemExit('Invalid HTTPS publishing URL: ' + key)

contact = {key: config.get(key) for key in ['supportEmail', 'privacyURL', 'supportURL', 'termsURL']}
legal = {'version': content['version'], 'updatedAt': content['updatedAt'],
         'appName': config['displayName'], 'publisherName': config['publisherName'],
         'accountMode': 'local-only', 'contact': contact, 'documents': content['documents']}
outputs = {'ios/Athar/app-legal.json': json.dumps(legal, ensure_ascii=False, indent=2) + '\n'}
draft = not email
escape = html.escape
navigation = '<nav aria-label="صفحات المساعدة">' + ' · '.join(
    f'<a href="{d["id"]}.html">{escape(d["title"])}</a>' for d in legal['documents']) + '</nav>'
style = 'body{margin:0;background:#f8f2e8;color:#282015;font:18px/1.9 system-ui,sans-serif}main{max-width:760px;margin:auto;padding:28px 20px}a{color:#734414}h1{font-size:30px}h2{font-size:22px;margin-top:30px}nav{padding:14px 0}footer{border-top:1px solid #baab90;margin-top:30px;padding-top:18px}aside{background:#fff3cf;padding:14px;border-radius:12px}a:focus-visible{outline:3px solid #734414;outline-offset:4px}'
for document in legal['documents']:
    banner = '<aside>مسودة محلية: أكمل بريد الدعم وراجع بيانات الناشر قبل النشر. هذه الملفات لم تُنشر على الإنترنت.</aside>' if draft else ''
    sections = ''.join(f'<section><h2>{escape(s["title"])}</h2><p>{escape(s["text"])}</p></section>' for s in document['sections'])
    support = f'<a href="mailto:{escape(quote(email, safe="@.+-"), quote=True)}">{escape(email)}</a>' if email else 'بريد الدعم لم يُحدد بعد.'
    outputs[f'support-site/{document["id"]}.html'] = f'<!doctype html>\n<html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="referrer" content="no-referrer"><title>{escape(document["title"])} — {escape(legal["appName"])}</title><style>{style}</style></head><body><main>{navigation}{banner}<h1>{escape(document["title"])}</h1><p>{escape(legal["appName"])} · الناشر: {escape(legal["publisherName"])}</p><p>آخر تحديث: <time datetime="{escape(legal["updatedAt"])}">{escape(legal["updatedAt"])}</time></p>{sections}<footer>للتواصل: {support}</footer></main></body></html>\n'
outputs['support-site/index.html'] = outputs['support-site/support.html']
outputs['support-site/.nojekyll'] = ''
for name, text in outputs.items():
    path = ROOT / name
    if args.check:
        if not path.is_file() or path.read_text() != text:
            raise SystemExit('Generated publishing file is missing/stale: ' + name)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
report = {'status': 'GENERATED_CONTENT_CURRENT', 'publicWebsite': 'NOT_DEPLOYED_BY_THIS_SCRIPT',
          'accountMode': 'local-only', 'supportEmailConfigured': bool(email), 'draftWithoutSupportEmail': draft,
          'publicPrivacyURLConfigured': bool(config.get('privacyURL')), 'publicSupportURLConfigured': bool(config.get('supportURL')),
          'files': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in outputs.items()}}
if not args.check:
    (ROOT / 'release/publishing-content-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
