"""Rebuild exact publisher timelines from a pinned, local response cache.

No network requests, number shifting, interpolation, or cross-recording reuse.
Cache: v3-reads.json and raw/{readID}-{surah}.json from the documented API.
This imports AYAH boundaries, not words or learner assessment.
"""
import argparse
import hashlib
import json
import zipfile
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def valid_spans(rows, count):
    if not isinstance(rows, list):
        raise ValueError('timeline must be an array')
    if any(not isinstance(v, dict) or type(v.get('ayah')) is not int for v in rows):
        raise ValueError('invalid ayah')
    # Some publisher documents include a separate unnumbered basmala. Only
    # discard zero when the remaining complete canonical 1...N already exists.
    spans = [[v['ayah'], v.get('start_time'), v.get('end_time')]
             for v in rows if v['ayah'] != 0]
    if [v[0] for v in spans] != list(range(1, count + 1)):
        raise ValueError('missing, repeated or reordered ayah')
    if not all(all(type(x) is int for x in v) and 0 <= v[1] < v[2] <= 21_600_000 for v in spans):
        raise ValueError('invalid span')
    if any(a[2] > b[1] for a, b in zip(spans, spans[1:])):
        raise ValueError('overlapping ayahs')
    return spans


def build(cache=None):
    receipt = json.loads((ROOT / 'content-sources/reciter-ayah-timings/receipt.json').read_text(encoding='utf-8'))
    archive = None
    if cache is None:
        raw = (ROOT/receipt['sourceArchive']['path']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != receipt['sourceArchive']['sha256']:
            raise ValueError('source archive integrity mismatch')
        archive = zipfile.ZipFile(io.BytesIO(raw))
    def read_bytes(name):
        # Never extract archive paths into the filesystem.
        return archive.read(name) if archive else (cache/name).read_bytes()
    raw_index = read_bytes('v3-reads.json')
    if hashlib.sha256(raw_index).hexdigest() != receipt['readIndexSHA256']:
        raise ValueError('read index integrity mismatch')
    reads = json.loads(raw_index)
    catalog = json.loads((ROOT / 'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))['reciters']
    counts = {s['number']: len(s['ayahs']) for s in json.loads((ROOT / 'ios/Athar/quran.json').read_text(encoding='utf-8'))}
    pins = {(v['server'], v['surah']): v['responseSHA256'] for v in receipt['tracks']}
    recordings, rejected = {}, []
    for reciter in catalog:
        matches = [r for r in reads if r['folder_url'] == reciter['server'] and r['soar_count'] == 114]
        if len(matches) != 1:
            continue
        read = matches[0]
        item = dict(readID=read['id'], reciterID=reciter['id'], recordingID=reciter['recordingID'], surahs={})
        recordings[reciter['server']] = item
        for surah in range(1, 115):
            raw = read_bytes(f"raw/{read['id']}-{surah}.json")
            expected = pins.get((reciter['server'], surah))
            if expected and hashlib.sha256(raw).hexdigest() != expected:
                raise ValueError('response integrity mismatch')
            try:
                spans = valid_spans(json.loads(raw), counts[surah])
            except (ValueError, KeyError, TypeError):
                rejected.append((reciter['server'], surah))
                continue
            # A previously rejected response cannot become approved merely
            # because upstream changes. Review and repin its receipt first.
            if expected is None:
                raise ValueError('unreviewed response became valid')
            item['surahs'][str(surah)] = spans
    result = json.dumps(dict(schema=1, recordings=recordings), ensure_ascii=False, separators=(',', ':')).encode()
    if hashlib.sha256(result).hexdigest() != receipt['outputSHA256']:
        raise ValueError('reconstructed output differs from pinned bundle')
    return result, rejected


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cache', type=Path, nargs='?', help='defaults to pinned source archive in repository')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result, rejected = build(args.cache)
    if args.output:
        args.output.write_bytes(result)
    print(json.dumps(dict(sha256=hashlib.sha256(result).hexdigest(), bytes=len(result), rejected=len(rejected))))
