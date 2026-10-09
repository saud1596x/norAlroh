"""Validate the checked-in static site without regenerating its pages."""
from pathlib import Path
from html.parser import HTMLParser
root = Path(__file__).resolve().parent
class LocalLinks(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('src', 'href') and value and not value.startswith(('https:', 'http:', 'mailto:', '#', 'data:')):
                name = value.split('#')[0].split('?')[0]
                if name and not (root / name).is_file():
                    raise SystemExit(f'Missing local asset: {name}')
for name in ('index.html', 'download.html', 'privacy.html', 'terms.html', 'support.html'):
    LocalLinks().feed((root / name).read_text(encoding='utf-8-sig'))
print('Noor website ready: five pages and all linked assets validated.')
