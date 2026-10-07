"""Stage official QCF V2 fonts; never substitutes them into the QCF4 renderer.

The manifest contains provenance and integrity metadata only, not Quran API data.
Use --record-manifest once to pin a reviewed upstream version. Normal runs enforce
the committed hashes. Fonts must only be distributed inside the finished app.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import struct
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://verses.quran.foundation/fonts/quran/hafs/v2/ttf/'
MANIFEST = ROOT / 'release/qcf-v2-manifest.json'

def download_font(url):
    """Retry transient transport/server failures, never change source or integrity."""
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                if response.status != 200 or response.url != url:
                    raise ValueError('Unexpected font source')
                return response.read(8_000_001)
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == 3:
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 3:
                raise
        time.sleep(2 ** attempt)

def inspect_font(data):
    if len(data) < 12 or len(data) > 8_000_000 or data[:4] != b'\x00\x01\x00\x00':
        raise ValueError('Invalid or oversized TrueType font')
    count = struct.unpack_from('>H', data, 4)[0]
    if not 1 <= count <= 100 or 12 + count * 16 > len(data):
        raise ValueError('Invalid font table directory')
    tables = {}
    for i in range(count):
        tag, _, offset, size = struct.unpack_from('>4sIII', data, 12 + i * 16)
        if offset + size > len(data):
            raise ValueError('Truncated font table')
        tables[tag] = (offset, size)
    if not {b'cmap', b'name', b'head', b'maxp', b'glyf', b'loca'} <= tables.keys():
        raise ValueError('Missing required font tables')
    off, size = tables[b'name']
    if size < 6:
        raise ValueError('Invalid name table')
    _, n, strings = struct.unpack_from('>HHH', data, off)
    if 6 + n * 12 > size:
        raise ValueError('Invalid name records')
    for i in range(n):
        platform, _, _, name_id, length, start = struct.unpack_from('>HHHHHH', data, off + 6 + i * 12)
        if name_id == 6 and platform in (0, 3):
            if strings + start + length > size:
                raise ValueError('Invalid font name bounds')
            return data[off + strings + start:off + strings + start + length].decode('utf-16-be')
    raise ValueError('Missing PostScript name')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--record-manifest', action='store_true')
    args = parser.parse_args()
    expected = {} if args.record_manifest else {x['page']: x for x in json.loads(MANIFEST.read_text())['fonts']}
    args.output.mkdir(parents=True, exist_ok=True)
    def fetch(page):
        name = f'p{page}.ttf'
        path = args.output / name
        if path.is_file():
            data = path.read_bytes()
        else:
            data = download_font(BASE + name)
        ps = inspect_font(data)
        if ps != f'QCF2{page:03}':
            raise ValueError(f'Wrong font for page {page}: {ps}')
        digest = hashlib.sha256(data).hexdigest()
        if not args.record_manifest and digest != expected[page]['sha256']:
            raise ValueError(f'Font version changed: page {page}; review before updating manifest')
        if not path.is_file():
            tmp = path.with_suffix('.part')
            tmp.write_bytes(data)
            os.replace(tmp, path)
        return {'page': page, 'file': name, 'postScriptName': ps, 'bytes': len(data), 'sha256': digest}
    fonts = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for font in pool.map(fetch, range(1, 605)):
            fonts.append(font)
            if len(fonts) % 50 == 0:
                print(f'Validated {len(fonts)}/604 fonts', flush=True)
    manifest = {'edition': 'QCF V2', 'mushafID': 1, 'source': BASE,
                'terms': 'https://api-docs.quran.foundation/legal/developer-terms/',
                'fontCount': 604, 'totalBytes': sum(f['bytes'] for f in fonts),
                'rendererMigrationComplete': False, 'fonts': fonts}
    if args.record_manifest:
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'validated': len(fonts), 'totalBytes': manifest['totalBytes'],
                      'rendererMigrationComplete': False}), flush=True)

if __name__ == '__main__':
    main()
