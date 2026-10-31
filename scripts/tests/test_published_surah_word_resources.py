"""Real imported playback coordinates; not audible synchronization evidence."""
import gzip
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
# Counts from the reviewed, source-pinned QUD v3.2.0 import after the 98 exact
# coordinate aliases. These are occurrence counts, including real repetitions;
# distinct native word coverage is checked independently below.
RECORDINGS = {
    'ali_al_huthaifi_mp3quran': {
        'id': 74, 'server': 'https://cdn.mp3quran.net/audio/ali-hudhaifi/r1/',
        'spans': 81137, 'words': 77429, 'missing': [],
        'package': '69538d785009f547305057b68e0028d91a552c0e118a3cfcb0eac1698a42a294',
        'candidate': '9e62c60277ab2dd839c7bea501efb5097190484b1a00eb6743cbf57a945b504a',
    },
    'saud_al_shuraim_mp3quran': {
        'id': 31, 'server': 'https://cdn.mp3quran.net/audio/saud-shuraim/r1/',
        'spans': 79293, 'words': 77425, 'missing': [529417, 529418, 529419, 529420],
        'package': '0b30f23f92874fc54caf7bb83633f3b62da22f992f95a596c1886a681bd36e56',
        'candidate': '5174657d5ca8501b015f3c00729fe14e86c9893956e2acef83d4d044357dcb98',
    },
}


class PublishedSurahWordResourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = (ROOT/'ios/Athar/surah-word-timings.json').read_bytes()
        cls.data = json.loads(cls.raw)
        cls.receipt = json.loads((ROOT/'content-sources/reciter-timings/published-surah-word-receipt.json').read_bytes())
        snapshot_raw = (ROOT/'content-sources/mushaf-snapshot.json.gz').read_bytes()
        cls.snapshot_sha = hashlib.sha256(snapshot_raw).hexdigest()
        corpus = json.loads((ROOT/'ios/Athar/quran.json').read_bytes())
        keys = [f"{s['number']}:{a['number']}" for s in corpus for a in s['ayahs']]
        cls.native = {r['id']: keys[r['verse_id']-1] for r in json.loads(gzip.decompress(snapshot_raw))['records']
                      if r['record_type'] == 'mushaf_word' and r['char_type_name'] == 'word'}
        cls.catalog = {r['server']:r for r in json.loads((ROOT/'ios/Athar/haramain-reciters.json').read_bytes())['reciters']}

    def test_bundle_pins_exact_edition_and_recording_identity(self):
        digest = hashlib.sha256(self.raw).hexdigest()
        self.assertEqual(self.receipt['outputSHA256'], digest)
        self.assertIn('"'+digest+'"', (ROOT/'ios/Athar/NoorSurahWordTimings.swift').read_text(encoding='utf-8'))
        self.assertEqual(self.data['nativeSnapshotSHA256'], self.snapshot_sha)
        self.assertEqual(self.snapshot_sha, '37544d69f3615fa2040be516eb2ba57c62fa25741332e3ba67f31f2a6df292d1')
        self.assertEqual(len(self.native), 77429)
        self.assertEqual(digest, '5873788999fdf57c524bb1241f0c89456684bac87ce228c57dfe6315774d6d78')
        aliases = (ROOT/'content-sources/reciter-timings/published-native-coordinate-aliases.json').read_bytes()
        self.assertEqual(hashlib.sha256(aliases).hexdigest(),
                         'e5ac4ba20abed63017550b3d6cc0f39f06d1c2f89ebb96e651ad69f178bb6f18')
        self.assertEqual(self.receipt['exactCoordinateBridgeSHA256'], hashlib.sha256(aliases).hexdigest())
        self.assertEqual(self.receipt['audioSourceIdentityProofSHA256'],
                         '188ca482f9927c10cd4477f79fb38f0702f27095531bdb1e756387f58c29b941')
        self.assertEqual(set(self.receipt['recordings']), set(RECORDINGS))
        self.assertEqual({r['reciterID'] for r in self.data['recordings'].values()}, {31,74})
        for server, recording in self.data['recordings'].items():
            self.assertEqual(recording['reciterID'], self.catalog[server]['id'])
            self.assertEqual(recording['recordingID'], self.catalog[server]['recordingID'])
            self.assertEqual(set(recording['surahs']), set(map(str,range(1,115))))

    def test_every_span_is_its_exact_native_ayah_with_real_source_clock_order(self):
        actual_total = 0
        for slug, expected in RECORDINGS.items():
            source = self.receipt['recordings'][slug]
            self.assertEqual(source['reciterID'], expected['id'])
            self.assertEqual(source['recordingID'], expected['id'])
            self.assertEqual(source['server'], expected['server'])
            self.assertEqual(source['publishedPackageSHA256'], expected['package'])
            self.assertEqual(source['boundCandidateSHA256'], expected['candidate'])
            self.assertEqual(source['surahs'], 114)
            self.assertEqual(source['spans'], expected['spans'])
            self.assertEqual(source['timedNativeWordIDs'], expected['words'])
            self.assertEqual(source['missingNativeWordIDs'], expected['missing'])
            recording = self.data['recordings'][expected['server']]
            count, native_words, timed_ayahs = 0, set(), set()
            for surah, spans in recording['surahs'].items():
                previous = 0
                for ayah, native, start, end in spans:
                    self.assertTrue(all(type(value) is int for value in (ayah, native, start, end)))
                    self.assertEqual(self.native[native], f'{surah}:{ayah}')
                    self.assertGreaterEqual(start, previous); self.assertGreater(end,start)
                    self.assertLessEqual(end,21_600_000);previous=end;count+=1
                    native_words.add(native); timed_ayahs.add(f'{surah}:{ayah}')
            self.assertEqual(count, source['spans'], slug)
            self.assertEqual(len(native_words), source['timedNativeWordIDs'], slug)
            self.assertEqual(set(self.native)-native_words, set(expected['missing']), slug)
            self.assertEqual(len(timed_ayahs), 6236 if expected['id'] == 74 else 6235, slug)
            actual_total += count
        self.assertEqual(actual_total, sum(row['spans'] for row in RECORDINGS.values()))

    def test_unmapped_ayahs_and_missing_publisher_basmala_remain_absent(self):
        for source in self.receipt['recordings'].values():
            spans = self.data['recordings'][source['server']]['surahs']
            for excluded in source['excludedOccurrences']:
                surah, ayah = excluded['verse'].split(':')
                self.assertFalse(any(row[0] == int(ayah) for row in spans[surah]))
        shuraim = next(r for r in self.data['recordings'].values() if r['reciterID']==31)
        self.assertFalse(any(row[0]==1 for row in shuraim['surahs']['1']))
        self.assertEqual({word for word, verse in self.native.items() if verse == '1:1'},
                         {529417,529418,529419,529420})
        hudhaify = next(r for r in self.data['recordings'].values() if r['reciterID']==74)
        self.assertEqual({row[1] for row in hudhaify['surahs']['1'] if row[0] == 1},
                         {529417,529418,529419,529420})

    def test_attribution_outside_privacy_and_release_payload_are_preserved(self):
        notice = (ROOT/'ios/Athar/Published-Surah-Word-Timings-SOURCE.txt').read_text(encoding='utf-8')
        self.assertIn('Wider Community',notice);self.assertIn('CC BY',notice)
        legal = (ROOT/'ios/Athar/NoorLegalContent.swift').read_text(encoding='utf-8')
        self.assertIn('Wider Community',legal)
        gate = (ROOT/'scripts/verify-release-ipa.py').read_text(encoding='utf-8')
        for resource in ['surah-word-timings.json','Published-Surah-Word-Timings-SOURCE.txt','Published-Surah-Word-Timings-LICENSE.txt']:
            self.assertIn("'"+resource+"'",gate)


if __name__ == '__main__':
    unittest.main()
