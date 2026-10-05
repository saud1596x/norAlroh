"""Copy Tanzil Uthmani 1.1 aya strings verbatim; do not normalize, retype or prepend a basmala."""
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'content-sources/tanzil'
raw = (folder / 'uthmani-app.xml').read_bytes()
receipt = json.loads((folder / 'app-receipt.json').read_text())
assert hashlib.sha256(raw).hexdigest() == receipt['sha256']
original_path = ROOT / 'content-sources/alquran-cloud/original-quran.json'
original_path.parent.mkdir(exist_ok=True)
target = ROOT / 'ios/Athar/quran.json'
if not original_path.exists():
    original_path.write_bytes(target.read_bytes())
metadata = json.loads(original_path.read_text())
xml = ET.fromstring(raw)
corpus = []
basmalas = {}
for chapter in xml.findall('sura'):
    number = int(chapter.attrib['index'])
    old = metadata[number - 1]
    assert old['number'] == number
    ayahs = []
    for aya in chapter.findall('aya'):
        ayahs.append({'number': int(aya.attrib['index']), 'text': aya.attrib['text']})
        if 'bismillah' in aya.attrib:
            assert aya.attrib['index'] == '1'
            basmalas[str(number)] = aya.attrib['bismillah']
    assert [a['number'] for a in ayahs] == list(range(1, len(ayahs) + 1))
    corpus.append({**old, 'ayahs': ayahs})
assert [s['number'] for s in corpus] == list(range(1, 115))
assert sum(len(s['ayahs']) for s in corpus) == 6236
assert set(basmalas) == {str(n) for n in range(2, 115) if n != 9}
target.write_text(json.dumps(corpus, ensure_ascii=False, separators=(',', ':')))
basmala_path = ROOT / 'ios/Athar/quran-basmalas.json'
basmala_path.write_text(json.dumps(basmalas, ensure_ascii=False, indent=2))
manifest_path = ROOT / 'ios/Athar/quran-resource-hashes.json'
manifest = json.loads(manifest_path.read_text())
for name in ['quran.json', 'quran-basmalas.json', 'AmiriQuran.ttf']:
    manifest[name] = hashlib.sha256((ROOT / 'ios/Athar' / name).read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
print(json.dumps({'source': receipt['url'], 'chapters': 114, 'verses': 6236, 'sourceTextAltered': False,
                  'separateBasmalas': len(basmalas), 'quranSHA256': manifest['quran.json']}))
