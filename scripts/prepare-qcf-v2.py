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

def checksum(data):
    data += b'\0' * (-len(data) % 4)
    return sum(struct.unpack('>' + 'I' * (len(data) // 4), data)) & 0xffffffff

def sanitize_cmap(data):
    """Remove only the upstream's truncated legacy Mac format-6 cmap.

    Keep all Unicode cmap bytes, glyph outlines, names and table offsets intact.
    Apple's ITMS-90853 rejects the six-byte format-6 header (minimum is 10).
    """
    result = bytearray(data)
    entries = {}
    for i in range(struct.unpack_from('>H', data, 4)[0]):
        pos = 12 + i * 16
        tag, _, off, size = struct.unpack_from('>4sIII', data, pos)
        entries[tag] = (pos, off, size)
    directory, off, size = entries[b'cmap']
    cmap = data[off:off + size]
    version, count = struct.unpack_from('>HH', cmap)
    if version != 0 or 4 + count * 8 > size:
        raise ValueError('Invalid cmap directory')
    kept, removed = [], []
    for i in range(count):
        record = cmap[4 + i * 8:12 + i * 8]
        platform, encoding, start = struct.unpack('>HHI', record)
        if start + 6 > size:
            raise ValueError('Truncated cmap subtable')
        fmt, length, language = struct.unpack_from('>HHH', cmap, start)
        if platform == 1 and encoding == 0 and fmt == 6 and length == 6 and language == 0:
            removed.append(start)
            continue
        if fmt not in (0, 4, 6):
            raise ValueError(f'Unreviewed cmap format: {fmt}')
        if start + length > size or length < {0: 262, 4: 16, 6: 10}[fmt]:
            raise ValueError('Invalid cmap length')
        if fmt == 0 and length != 262:
            raise ValueError('Invalid format-0 length')
        if fmt == 6 and length != 10 + 2 * struct.unpack_from('>H', cmap, start + 8)[0]:
            raise ValueError('Invalid format-6 entry count')
        kept.append(record)
    if not kept:
        raise ValueError('No usable cmap')
    if not removed:
        return data, False
    new = bytearray(cmap)
    struct.pack_into('>H', new, 2, len(kept))
    new[4:4 + len(kept) * 8] = b''.join(kept)
    new[4 + len(kept) * 8:4 + count * 8] = b'\0' * (8 * len(removed))
    for start in removed:
        new[start:start + 6] = b'\0' * 6
    result[off:off + size] = new
    struct.pack_into('>I', result, directory + 4, checksum(bytes(new)))
    _, head, _ = entries[b'head']
    struct.pack_into('>I', result, head + 8, 0)
    struct.pack_into('>I', result, head + 8, (0xb1b0afba - checksum(bytes(result))) & 0xffffffff)
    return bytes(result), True

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
        upstream_digest = hashlib.sha256(data).hexdigest()
        if not args.record_manifest and 'upstreamSha256' in expected[page] and upstream_digest == expected[page]['sha256']:
            _, changed = sanitize_cmap(data)
            if changed:
                raise ValueError('Pinned repaired font still has malformed cmap')
            ps = inspect_font(data)
            return expected[page]
        ps = inspect_font(data)
        if ps != f'QCF2{page:03}':
            raise ValueError(f'Wrong font for page {page}: {ps}')
        if not args.record_manifest and upstream_digest != expected[page].get('upstreamSha256', expected[page]['sha256']):
            raise ValueError(f'Font version changed: page {page}; review before updating manifest')
        data, repaired = sanitize_cmap(data)
        digest = hashlib.sha256(data).hexdigest()
        if not args.record_manifest and digest != expected[page]['sha256']:
            raise ValueError(f'Bundled font hash mismatch: page {page}')
        tmp = path.with_suffix('.part')
        tmp.write_bytes(data)
        os.replace(tmp, path)
        entry = {'page': page, 'file': name, 'postScriptName': ps, 'bytes': len(data), 'sha256': digest}
        if repaired:
            entry.update(upstreamSha256=upstream_digest, repair='Remove truncated Macintosh format-6 cmap; preserve Unicode mappings and all glyph tables')
        return entry
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
