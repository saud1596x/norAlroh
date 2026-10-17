"""Stage pinned original QCF V4 fonts and their exact COLR-v0/CPAL layers.

No font modification, glyph replacement, inferred Tajweed rules or whole-word
coloring. Generated assets are bundled only inside the integrated application.
"""
import argparse, concurrent.futures, hashlib, importlib.util, json, struct, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'release/qcf-v4-manifest.json'
BASE = 'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/'
spec = importlib.util.spec_from_file_location('qcf_stage', ROOT / 'scripts/prepare-qcf-v2.py')
qcf = importlib.util.module_from_spec(spec); spec.loader.exec_module(qcf)

def digest(b): return hashlib.sha256(b).hexdigest()

def layers(data):
    tables = {}
    for i in range(struct.unpack_from('>H', data, 4)[0]):
        tag, _, off, size = struct.unpack_from('>4sIII', data, 12 + i * 16)
        if off + size > len(data): raise ValueError('Truncated font')
        tables[tag] = data[off:off + size]
    colr, cpal = tables[b'COLR'], tables[b'CPAL']
    version, count, base, layer, n = struct.unpack_from('>HHIIH', colr)
    if version != 0 or base + count * 6 > len(colr) or layer + n * 4 > len(colr):
        raise ValueError('Only bounded original COLR v0 supported')
    pv, entries, palettes, colors, off = struct.unpack_from('>HHHHI', cpal)
    if pv not in (0, 1) or palettes < 2 or off + colors * 4 > len(cpal): raise ValueError('Invalid CPAL')
    palette = []
    for i in range(2):
        start = struct.unpack_from('>H', cpal, 12 + 2 * i)[0]
        if start + entries > colors: raise ValueError('Invalid palette range')
        values = []
        for j in range(entries):
            b, g, r, a = struct.unpack_from('4B', cpal, off + (start + j) * 4)
            values.append([r, g, b, a])
        palette.append(values)
    result = {}
    for i in range(count):
        glyph, first, size = struct.unpack_from('>HHH', colr, base + i * 6)
        if first + size > n or not size: raise ValueError('Invalid color glyph')
        parts = [list(struct.unpack_from('>HH', colr, layer + j * 4)) for j in range(first, first + size)]
        if any(c != 65535 and c >= entries for _, c in parts): raise ValueError('Invalid color index')
        result[str(glyph)] = parts
    return {'schema': 1, 'palettes': palette, 'layers': result}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--archive', type=Path)
    p.add_argument('--record-manifest', action='store_true')
    a = p.parse_args(); a.output.mkdir(parents=True, exist_ok=True)
    expected = {} if a.record_manifest else {e['page']: e for e in json.loads(MANIFEST.read_text())['fonts']}
    archive = zipfile.ZipFile(a.archive) if a.archive else None
    def stage(page):
        name = f't4-p{page}.ttf'; path = a.output / name
        data = archive.read(f'p{page}.ttf') if archive else path.read_bytes() if path.exists() else qcf.download_font(BASE + f'p{page}.ttf')
        family = qcf.inspect_font(data)
        if family not in (f'QCF4{page:03}_COLOR', f'QCF4{page:03}_COLOR-Regular'): raise ValueError(f'Wrong page {page}: {family}')
        meta = (json.dumps(layers(data), separators=(',', ':')) + '\n').encode()
        entry = {'page': page, 'file': name, 'postScriptName': family, 'bytes': len(data), 'sha256': digest(data), 'layersSha256': digest(meta)}
        if not a.record_manifest and entry != expected[page]: raise ValueError(f'Upstream changed: page {page}')
        path.write_bytes(data); path.with_suffix('.json').write_bytes(meta)
        return entry
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool: fonts = list(pool.map(stage, range(1, 605)))
    if a.record_manifest:
        MANIFEST.write_text(json.dumps({'edition': 'Original QCF V4 COLR v0', 'mushafID': 19, 'source': BASE,
          'terms': 'https://api-docs.quran.foundation/legal/developer-terms/', 'fontCount': 604,
          'fonts': fonts}, indent=2) + '\n')
    print(json.dumps({'validated': len(fonts), 'bytes': sum(e['bytes'] for e in fonts)}))

if __name__ == '__main__': main()
