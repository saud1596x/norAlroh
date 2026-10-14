import json
from pathlib import Path
import unittest
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]


class ReciterCatalogTests(unittest.TestCase):
    def test_catalog_requires_complete_quran_and_safe_distinct_sources(self):
        data = json.loads((ROOT/'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))
        self.assertEqual(data['schema'], 1)
        rows = data['reciters']
        self.assertEqual(len(rows), 20)
        self.assertEqual(len({r['id'] for r in rows}), len(rows))
        self.assertEqual(len({r['server'] for r in rows}), len(rows))
        for row in rows:
            source = urlsplit(row['server'])
            self.assertEqual(source.scheme, 'https')
            self.assertEqual(source.hostname, 'cdn.mp3quran.net')
            self.assertIsNone(source.username)
            self.assertFalse(source.query or source.fragment)
            self.assertTrue(source.path.startswith('/audio/') and source.path.endswith('/'))
            self.assertEqual(len(set(row['surahs'])), len(row['surahs']))
            self.assertEqual(set(row['surahs']), set(range(1, 115)))
            self.assertTrue(all(type(n) is int and 1 <= n <= 114 for n in row['surahs']))
        by_id = {r['id']: r for r in rows}
        self.assertNotIn(21188, by_id)
        self.assertNotIn(41, by_id)
        self.assertEqual(len(by_id[21136]['surahs']), 114)
        self.assertEqual(len(by_id[21181]['surahs']), 114)


if __name__ == '__main__':
    unittest.main()
