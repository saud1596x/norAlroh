"""Offline additive QUD v3.2.0 import. Never rewrites existing clocks or IDs."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools/reciter_alignment'))
import published_coordinates as coordinates

SOURCES = {
    'mishary_rashid_al_afasy_mp3quran': (1000001, 'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/', '2ef64637e14b657fc354c6aab718344d61102b6a4934a32ff214c77bd1e3db69'),
    'maher_al_muaiqly_qdc': (1000002, 'https://download.quranicaudio.com/quran/maher_almu3aiqly/year1440/', '538c8ec00170eacfd908872177d4d5446a062f9a0f98c8ddbad467cd78b9b567'),
    'mahmoud_khalil_al_husary_mp3quran': (1000003, 'https://cdn.mp3quran.net/audio/mahmoud-husary/r1/', '478e20aa0bdbb3d4a89a55e44788989843e2a46efb99ecd11712791d7b4dbc7e'),
}


def contiguous_words(rows):
    rows = sorted(rows)
    if not rows or [position for position, _ in rows] != list(range(1,len(rows)+1)):
        raise ValueError('Noncontiguous publisher word coordinates')
    return [text for _,text in rows]


def expanded_word_tier(compressed, limit=32_000_000):
    with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as stream:
        expanded = stream.read(limit+1)
    if len(expanded) > limit: raise ValueError('Oversized expanded word tier')
    return expanded


def exact_audio_identity(proof, slug, publisher_urls, base):
    rows = [r for r in proof['records'] if r['slug'] == slug]
    if len(rows) != 114 or {r['surah'] for r in rows} != set(range(1,115)):
        raise ValueError('Incomplete or repeated source identity proof')
    for row in rows:
        expected = base + f"{row['surah']:03}.mp3"
        if (row['publisherURL'] != publisher_urls[str(row['surah'])] or row['status'] != 200
                or row['appURL'] != expected or row['finalURL'] != expected
                or row.get('identityVerified') is not True or row.get('contentType') != 'audio/mpeg'):
            raise ValueError('Foreign/unverified exact source audio URL')


def build(inputs, proof_path, root=ROOT):
    script = json.loads(coordinates.pinned(inputs/'v3.2.0-digital_khatt_v2_script.json', coordinates.SCRIPT_SHA256))
    authored = json.loads(coordinates.pinned(root/'content-sources/recitation-word-script.json', coordinates.AUTHORED_SCRIPT_SHA256))['groups']
    native_raw = coordinates.pinned(root/'content-sources/mushaf-snapshot.json.gz', coordinates.NATIVE_SNAPSHOT_SHA256)
    snapshot = json.loads(gzip.decompress(native_raw))
    corpus = json.loads((root/'ios/Athar/quran.json').read_bytes())
    keys = [f"{s['number']}:{a['number']}" for s in corpus for a in s['ayahs']]
    native, publisher = {}, {}
    for row in snapshot['records']:
        if row['record_type'] == 'mushaf_word' and row.get('char_type_name') == 'word':
            native.setdefault(keys[row['verse_id']-1], []).append(row)
    for key, value in script.items():
        if coordinates.normalize(value['text']):
            verse, position = key.rsplit(':',1); publisher.setdefault(verse,[]).append((int(position),value['text']))
    aliases = coordinates.published_aliases(root/coordinates.PUBLISHED_ALIASES_PATH)
    mapping = {}
    for verse, groups in authored.items():
        words = sorted(native[verse],key=lambda r:r['position_in_verse'])
        source = contiguous_words(publisher[verse])
        if len(words) != len(groups) or any(r['page_number'] != g[0] for r,g in zip(words,groups)):
            raise ValueError('Authored native edition mismatch')
        bound = coordinates.map_published_words(verse, groups, source, [r['id'] for r in words], aliases)
        if bound is None: raise ValueError('Unresolved exact native coordinate: '+verse)
        mapping[verse] = ([r['id'] for r in words], bound)
    all_ids = {r['id'] for rows in native.values() for r in rows}
    proof_raw = proof_path.read_bytes(); proof = json.loads(proof_raw)
    catalog, timings, receipts = [], {}, {}
    for slug, (identifier, base, package_digest) in SOURCES.items():
        package = coordinates.pinned(inputs/(slug+'.zip'),package_digest)
        with zipfile.ZipFile(io.BytesIO(package)) as archive:
            metadata = json.loads(archive.read('catalog.json'))
            if archive.getinfo('word_timestamps.json.gz').file_size > 4_000_000: raise ValueError('Oversized word tier')
            compressed = archive.read('word_timestamps.json.gz'); expanded = expanded_word_tier(compressed)
            timing = json.loads(expanded)
        meta = timing['_meta']
        if (meta['slug'] != slug or meta['schema_version'] != 3 or meta['script_sha256'] != coordinates.SCRIPT_SHA256
                or meta['units'] != 'ms' or meta['tier'] != 'word' or meta['riwayah'] != 'hafs'
                or meta['audio_category'] != 'by_surah'):
            raise ValueError('Foreign publisher timing contract')
        exact_audio_identity(proof,slug,metadata['audio']['chapter_urls'],base)
        chapters, canonical = {}, {}
        for row in timing['rows']:
            verse = row[0]; number, ayah = map(int,verse.split(':'))
            spans = coordinates.bind_row(row,*mapping[verse])
            chapters.setdefault(str(number),[]).extend([[ayah,*span] for span in spans])
            if row[3]: canonical[verse] = canonical.get(verse,0)+1
        seen = {span[1] for rows in chapters.values() for span in rows}
        if seen != all_ids or set(chapters) != set(map(str,range(1,115))) or canonical != dict.fromkeys(keys,1):
            raise ValueError('Incomplete native word/verse coverage')
        for rows in chapters.values():
            rows.sort(key=lambda s:(s[2],s[3]))
            if any(a[3] > b[2] for a,b in zip(rows,rows[1:])): raise ValueError('Source word clocks overlap')
        catalog.append({'id':identifier,'recordingID':identifier,'name':metadata['name_ar'], 'server':base,
                        'surahs':list(range(1,115)), 'publisherSlug':slug,
                        'recordingLabel':'QuranicAudio 1440' if slug=='maher_al_muaiqly_qdc' else 'MP3Quran r1'})
        timings[base] = {'reciterID':identifier,'recordingID':identifier,'surahs':chapters}
        receipts[slug] = {'internalID':identifier,'server':base,'publishedPackageSHA256':package_digest,
            'publishedPackageBytes':len(package),'wordTierSHA256':hashlib.sha256(compressed).hexdigest(),
            'occurrences':len(timing['rows']),'nativeWords':len(seen),'verses':len(canonical),'surahs':len(chapters),
            'excludedOccurrences':0,'interpolatedClocks':0,'globalClockOverlaps':0}
    encode = lambda d: (json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n').encode()
    catalog_raw = encode({'schema':1,'namespace':'NOOR_INTERNAL_RECORDING_IDS_NOT_PROVIDER_IDS','reciters':catalog})
    timing_raw = encode({'schema':1,'nativeSnapshotSHA256':coordinates.NATIVE_SNAPSHOT_SHA256,'recordings':timings})
    receipt = {'source':'https://github.com/QUD-Technologies/quranic-universal-audio/releases/tag/v3.2.0',
        'attribution':'Wider Community','license':'CC BY 4.0','namespace':'NOOR_INTERNAL_RECORDING_IDS_NOT_PROVIDER_IDS',
        'nativeSnapshotSHA256':coordinates.NATIVE_SNAPSHOT_SHA256,'publisherScriptSHA256':coordinates.SCRIPT_SHA256,
        'preservedExactCoordinateBridgeSHA256':coordinates.PUBLISHED_ALIASES_SHA256,
        'audioSourceIdentityProofSHA256':hashlib.sha256(proof_raw).hexdigest(),
        'catalogSHA256':hashlib.sha256(catalog_raw).hexdigest(),'timingSHA256':hashlib.sha256(timing_raw).hexdigest(),
        'scope':'COMPLETE_NATIVE_COORDINATE_COVERAGE_NOT_INDEPENDENT_ACOUSTIC_REVIEW','recordings':receipts}
    return catalog_raw,timing_raw,receipt,proof_raw


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--inputs',type=Path,required=True);parser.add_argument('--identity-proof',type=Path,required=True)
    args=parser.parse_args();catalog,timing,receipt,proof=build(args.inputs,args.identity_proof)
    (ROOT/'ios/Athar/additional-reciters.json').write_bytes(catalog)
    (ROOT/'ios/Athar/additional-surah-word-timings.json').write_bytes(timing)
    (ROOT/'content-sources/reciter-timings/additional-recordings-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    (ROOT/'content-sources/reciter-timings/additional-audio-identity-proof.json').write_bytes(proof)
    print(json.dumps(receipt,ensure_ascii=False,indent=2))
