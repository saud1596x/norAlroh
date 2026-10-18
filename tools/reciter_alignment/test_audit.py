"""Resume/coverage policy fixtures only, never real-audio accuracy evidence."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from audit import SCHEMA, AYAH_POLICY, complete_report, fingerprint, library_coverage, write_json
from quran_ctc import REVISION
from verify_catalog import LocalDeadline, align_windows, validate_ayah_windows

ROOT = Path(__file__).resolve().parents[2]


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads((ROOT/'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))['reciters']
        self.inputs = fingerprint(ROOT)

    def report(self):
        return {'auditSchema': SCHEMA, 'inputFingerprint': self.inputs, 'surah': 1,
                'modelRevision': REVISION, 'ayahWindowPolicy': AYAH_POLICY,
                'selectedReciterIDs': [r['id'] for r in self.catalog],
                'records': [{'reciterID': r['id'], 'recordingID': r['recordingID'],
                    'audioURL': r['server']+'001.mp3', 'audioSHA256': 'a'*64, 'status': 'REJECTED'}
                    for r in self.catalog],
                'controls': [{'name': n, 'rejected': True} for n in ('silence','noise','wrong-known-text')]}

    def test_resume_requires_policy_recording_identity_complete_catalog_and_negative_controls(self):
        report = self.report()
        self.assertTrue(complete_report(report, self.inputs, 1, self.catalog))
        for field, value in [('inputFingerprint', {'sha256': 'changed'}),
                             ('records', report['records'][:-1]), ('controls', report['controls'][:-1]),
                             ('modelRevision', 'another-model'), ('ayahWindowPolicy', None),
                             ('auditSchema', 1)]:
            altered = copy.deepcopy(report); altered[field] = value
            self.assertFalse(complete_report(altered, self.inputs, 1, self.catalog))
        report['records'][0]['recordingID'] += 1
        self.assertFalse(complete_report(report, self.inputs, 1, self.catalog))

    def test_full_scope_lists_every_missing_track_and_never_promotes_candidates(self):
        with tempfile.TemporaryDirectory() as folder:
            report = self.report(); report['records'] = report['records'][:1]
            report['records'][0]['status'] = 'MEASURED_CANDIDATE_REQUIRES_REVIEW'
            write_json(Path(folder)/'001/report.json', report)
            audit = library_coverage(ROOT, [folder])
        self.assertEqual(audit['expectedRecordings'], 2280)
        self.assertEqual(audit['observedRecordings'], 1)
        self.assertEqual(audit['currentPolicyCandidates'], 1)
        self.assertEqual(audit['verifiedWholeRecordings'], 0)
        self.assertTrue(all(len(r['tracks']) == 114 for r in audit['readers']))
        self.assertFalse(any(t['productionWordTrackingVerified'] for r in audit['readers'] for t in r['tracks']))

    def test_changed_policy_keeps_old_candidates_distinct_from_current_rejections(self):
        with tempfile.TemporaryDirectory() as folder:
            report = self.report(); report['records'] = report['records'][:1]
            report['records'][0]['status'] = 'MEASURED_CANDIDATE_REQUIRES_REVIEW'
            report['inputFingerprint'] = {'sha256': 'old'}
            write_json(Path(folder)/'old/001/report.json', report)
            current = self.report(); current['records'] = current['records'][:1]
            write_json(Path(folder)/'new/001/report.json', current)
            audit = library_coverage(ROOT, [Path(folder)/'new', Path(folder)/'old'])
        self.assertEqual(audit['legacyCandidatesRequireRecheck'], 0)
        self.assertEqual(audit['currentPolicyCandidates'], 0)
        self.assertEqual(audit['readers'][0]['tracks'][0]['status'], 'REJECTED')

    def test_missing_duplicate_and_out_of_duration_ayah_windows_are_rejected(self):
        for windows in ([[1,0,100]], [[1,0,100],[1,200,300]],
                        [[1,0,250],[2,200,300]], [[1,0,100],[2,200,2100]]):
            with self.subTest(windows=windows), self.assertRaises(ValueError):
                validate_ayah_windows(windows, {1: [(1,'a')], 2: [(2,'b')]}, 2000)

    def test_deadline_checkpoint_resumes_exact_ayah_without_repeating_or_claiming_complete(self):
        class PolicyAligner:
            calls = 0
            def align(self, pcm, words):
                self.calls += 1
                start = 0 if words[0][0] == 1 else 400
                return {'spans': [[words[0][0],start,start+100]], 'minimumWordPosterior': .9}
        aligner = PolicyAligner(); record = {}
        def stop_after_checkpoint():
            raise LocalDeadline('Injected time boundary, not an acoustic result')
        with self.assertRaises(LocalDeadline):
            align_windows(aligner, np.zeros(32000), [[1,0,200],[2,1000,1200]],
                          {1:[(1,'a')],2:[(2,'b')]}, record, stop_after_checkpoint)
        self.assertEqual(list(record['ayahResults']), ['1'])
        self.assertNotIn('spans', record)
        align_windows(aligner, np.zeros(32000), [[1,0,200],[2,1000,1200]],
                      {1:[(1,'a')],2:[(2,'b')]}, record, lambda: None)
        self.assertEqual(aligner.calls, 2)
        self.assertEqual([s[0] for s in record['spans']], [1,2])


if __name__ == '__main__':
    unittest.main()
