"""Exact character comparison against pinned, unmodified Tanzil XML. No normalization can hide a mismatch."""
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'content-sources/tanzil'
raw = (folder / 'uthmani-app.xml').read_bytes()
receipt = json.loads((folder / 'app-receipt.json').read_text())
quran = json.loads((ROOT / 'ios/Athar/quran.json').read_text())
basmalas = json.loads((ROOT / 'ios/Athar/quran-basmalas.json').read_text())
xml = ET.fromstring(raw)
expected = {f"{s.attrib['index']}:{a.attrib['index']}": a.attrib['text']
            for s in xml.findall('sura') for a in s.findall('aya')}
current = {f"{s['number']}:{a['number']}": a['text'] for s in quran for a in s['ayahs']}
ordered = [f"{s['number']}:{a['number']}" for s in quran for a in s['ayahs']]
source_order = [f"{s.attrib['index']}:{a.attrib['index']}" for s in xml.findall('sura') for a in s.findall('aya')]
mismatches = [key for key in expected if expected[key] != current.get(key)]
source_basmalas = {s.attrib['index']: a.attrib['bismillah']
                   for s in xml.findall('sura') for a in s.findall('aya') if 'bismillah' in a.attrib}
checks = {
    'sourceXMLPinnedHash': hashlib.sha256(raw).hexdigest() == receipt['sha256'],
    'all114Chapters': [s['number'] for s in quran] == list(range(1, 115)),
    'all6236VersesExactlyOnceInSourceOrder': len(ordered) == len(set(ordered)) == 6236 and ordered == source_order,
    'everyAyaIdenticalByUnicodeCodepoint': not mismatches and set(current) == set(expected),
    'all112SeparateBasmalasVerbatim': basmalas == source_basmalas and len(basmalas) == 112,
    'ikhlasAndNasEveryCharacterVerified': all(current.get(key) == expected[key] for key in expected if key.startswith(('112:', '114:'))),
    'noInjectedHTMLOrReplacementCharacters': not any(any(c in text for c in ['\ufffd', '<', '>', '&']) for text in current.values()),
}
report = {'status': 'EXACT_SOURCE_COPY_VERIFIED' if all(checks.values()) else 'FAIL',
          'source': receipt['url'], 'edition': receipt['edition'], 'checks': checks,
          'comparedVerses': len(expected), 'mismatches': mismatches,
          'comparisonNormalization': 'NONE; exact Unicode codepoint equality',
          'nativeRendering': 'NOT_TESTED', 'religiousAndPrintedPageReview': 'PENDING',
          'scope': 'Verbatim source-copy integrity. This does not certify font shaping, QCF glyph semantics or specialist approval.'}
(ROOT / 'release/quran-text-integrity.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(not all(checks.values()))
