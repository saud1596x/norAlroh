"""Additional published clocks and native bindings, not audible approval."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    1000001: ('mishary_rashid_al_afasy_mp3quran', 'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/', '2ef64637e14b657fc354c6aab718344d61102b6a4934a32ff214c77bd1e3db69'),
    1000002: ('maher_al_muaiqly_qdc', 'https://download.quranicaudio.com/quran/maher_almu3aiqly/year1440/', '538c8ec00170eacfd908872177d4d5446a062f9a0f98c8ddbad467cd78b9b567'),
    1000003: ('mahmoud_khalil_al_husary_mp3quran', 'https://cdn.mp3quran.net/audio/mahmoud-husary/r1/', '478e20aa0bdbb3d4a89a55e44788989843e2a46efb99ecd11712791d7b4dbc7e'),
}


class AdditionalReciterResourcesTests(unittest.TestCase):
    def test_importer_rejects_foreign_or_incomplete_source_identity(self):
        spec = importlib.util.spec_from_file_location('additional_import',ROOT/'scripts/import-additional-surah-word-timings.py')
        importer = importlib.util.module_from_spec(spec); spec.loader.exec_module(importer)
        self.assertEqual(importer.contiguous_words([(2,'second'),(1,'first')]), ['first','second'])
        for coordinates in [[], [(1,'first'),(3,'third')], [(1,'first'),(1,'duplicate')]]:
            with self.assertRaisesRegex(ValueError,'Noncontiguous'):
                importer.contiguous_words(coordinates)
        self.assertEqual(importer.expanded_word_tier(gzip.compress(b'abcde'),5), b'abcde')
        with self.assertRaisesRegex(ValueError,'Oversized'):
            importer.expanded_word_tier(gzip.compress(b'abcde'),4)
        proof = json.loads((ROOT/'content-sources/reciter-timings/additional-audio-identity-proof.json').read_bytes())
        slug, base, _ = SOURCES[1000002]
        rows = [r for r in proof['records'] if r['slug']==slug]
        publishers = {str(r['surah']):r['publisherURL'] for r in rows}
        importer.exact_audio_identity(proof,slug,publishers,base)
        changed = json.loads(json.dumps(proof))
        next(r for r in changed['records'] if r['slug']==slug)['finalURL'] = 'https://cdn.mp3quran.net/audio/maher-muaiqly/r1/001.mp3'
        with self.assertRaisesRegex(ValueError,'Foreign/unverified'):
            importer.exact_audio_identity(changed,slug,publishers,base)
        with self.assertRaisesRegex(ValueError,'Incomplete'):
            importer.exact_audio_identity({'records':rows[:-1]},slug,publishers,base)

    def test_additive_payload_covers_exact_native_words_without_altering_legacy_bytes(self):
        path = ROOT/'ios/Athar/additional-surah-word-timings.json'
        self.assertTrue(path.is_file(), 'No additive complete published timing payload')
        data = json.loads(path.read_bytes())
        self.assertEqual(data['schema'], 1)
        self.assertEqual(data['nativeSnapshotSHA256'], '37544d69f3615fa2040be516eb2ba57c62fa25741332e3ba67f31f2a6df292d1')
        corpus = json.loads((ROOT/'ios/Athar/quran.json').read_bytes())
        keys = [f"{s['number']}:{a['number']}" for s in corpus for a in s['ayahs']]
        raw = (ROOT/'content-sources/mushaf-snapshot.json.gz').read_bytes()
        native = {r['id']: keys[r['verse_id']-1] for r in json.loads(gzip.decompress(raw))['records']
                  if r['record_type']=='mushaf_word' and r['char_type_name']=='word'}
        self.assertEqual(set(data['recordings']), {r[1] for r in SOURCES.values()})
        for identifier, (slug, server, _) in SOURCES.items():
            recording = data['recordings'][server]
            self.assertEqual((recording['reciterID'], recording['recordingID']), (identifier, identifier))
            self.assertEqual(set(recording['surahs']), set(map(str, range(1,115))))
            seen, verses = set(), set()
            for surah, spans in recording['surahs'].items():
                previous = 0
                for ayah, word, start, end in spans:
                    self.assertEqual(native[word], f'{surah}:{ayah}')
                    self.assertTrue(all(type(x) is int for x in [ayah, word, start, end]))
                    self.assertGreaterEqual(start, previous); self.assertGreater(end,start)
                    previous=end; seen.add(word); verses.add(f'{surah}:{ayah}')
            self.assertEqual(seen, set(native), slug); self.assertEqual(len(seen), 77429)
            self.assertEqual(verses, set(keys)); self.assertIn('1:1', verses)
        original_basmala_clocks = {
            1000001: [[6360,6900],[6900,7680],[7680,8810],[8810,12270]],
            1000002: [[7710,8340],[8340,9140],[9140,10260],[10260,13520]],
            1000003: [[6464,6934],[6934,7654],[7654,8814],[8814,11104]],
        }
        for identifier, clocks in original_basmala_clocks.items():
            spans = data['recordings'][SOURCES[identifier][1]]['surahs']['1']
            self.assertEqual([s for s in spans if s[0]==1],
                             [[1,529417+i,*clock] for i,clock in enumerate(clocks)])
        for name, digest in {
            'haramain-reciters.json': '3677ce535894a7c0a0ab9c74f5ce73b128d4e5c4050edd537e9287a5000b2568',
            'surah-word-timings.json': '5873788999fdf57c524bb1241f0c89456684bac87ce228c57dfe6315774d6d78',
            'reciter-word-timings.json': 'c3364cd2f2f76de78274e24d6b7b4e0ce8a74f7c5f8dd64fad9cad6826d2eb9d'}.items():
            self.assertEqual(hashlib.sha256((ROOT/'ios/Athar'/name).read_bytes()).hexdigest(), digest)

    def test_catalog_and_all_114_source_identity_receipts_bind_the_new_namespace(self):
        path = ROOT/'ios/Athar/additional-reciters.json'
        self.assertTrue(path.is_file(), 'No pinned additional recording catalog')
        catalog = json.loads(path.read_bytes())
        self.assertEqual(catalog['namespace'], 'NOOR_INTERNAL_RECORDING_IDS_NOT_PROVIDER_IDS')
        self.assertEqual({r['id'] for r in catalog['reciters']}, set(SOURCES))
        receipt = json.loads((ROOT/'content-sources/reciter-timings/additional-recordings-receipt.json').read_bytes())
        proof_raw = (ROOT/'content-sources/reciter-timings/additional-audio-identity-proof.json').read_bytes()
        self.assertEqual(receipt['audioSourceIdentityProofSHA256'], hashlib.sha256(proof_raw).hexdigest())
        proof = json.loads(proof_raw)['records']; self.assertEqual(len(proof),342)
        for row in catalog['reciters']:
            slug, server, digest = SOURCES[row['id']]
            self.assertEqual(row['recordingID'],row['id']); self.assertEqual(row['server'],server)
            self.assertEqual(row['surahs'],list(range(1,115)))
            self.assertEqual(receipt['recordings'][slug]['publishedPackageSHA256'],digest)
            rows = [r for r in proof if r['slug']==slug]
            self.assertEqual({r['surah'] for r in rows},set(range(1,115)))
            for p in rows:
                self.assertEqual(p['status'],200); self.assertTrue(p['identityVerified'])
                self.assertEqual(p['finalURL'],server+f"{p['surah']:03}.mp3")
        runtime = (ROOT/'ios/Athar/NoorAdditionalReciters.swift').read_text(encoding='utf8')
        for name in ['additional-reciters.json','additional-surah-word-timings.json']:
            self.assertIn('"'+hashlib.sha256((ROOT/'ios/Athar'/name).read_bytes()).hexdigest()+'"', runtime)

    def test_required_timing_license_and_source_notice_are_in_the_distribution_gate(self):
        license_raw = (ROOT/'ios/Athar/Additional-Reciter-Timings-LICENSE.txt').read_bytes()
        self.assertEqual(hashlib.sha256(license_raw).hexdigest(), '26410dc4551397fb7259024eb36c70cbed23bc9816b6de1e9a7f721f43d5976d')
        notice = (ROOT/'ios/Athar/Additional-Reciter-Timings-SOURCE.txt').read_text()
        self.assertIn('Wider Community',notice);self.assertIn('CC BY 4.0',notice)
        for slug, _, _ in SOURCES.values():self.assertIn(slug,notice)
        gate = (ROOT/'scripts/verify-release-ipa.py').read_text()
        for name in ['additional-reciters.json','additional-surah-word-timings.json',
                     'Additional-Reciter-Timings-SOURCE.txt','Additional-Reciter-Timings-LICENSE.txt']:
            self.assertIn("'"+name+"'",gate)


if __name__ == '__main__': unittest.main()
