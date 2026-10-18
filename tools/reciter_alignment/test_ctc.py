"""Algorithm fixtures only; these are not generated-audio acceptance tests."""
import unittest
from unittest.mock import patch
import hashlib
from pathlib import Path
import tempfile
import numpy as np
from ctc import viterbi, normalize, validate_recording_spans
from quran_ctc import QuranAligner, verify_assets


class AssetPinTests(unittest.TestCase):
    def test_editable_receipt_cannot_authorize_modified_weights(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);(folder/'weights').write_bytes(b'original')
            pin=hashlib.sha256(b'original').hexdigest()
            with patch('quran_ctc.FILES',{'weights':pin}):
                verify_assets(folder)
                (folder/'weights').write_bytes(b'modified')
                (folder/'download-receipt.json').write_text('{"publisherWeightsSHA256Verified":true}')
                with self.assertRaises(ValueError):verify_assets(folder)

    def test_quran_projection_normalizer_drops_marks_but_keeps_letters(self):
        aligner=object.__new__(QuranAligner)
        self.assertEqual(aligner.normalizer('ٱلْحَمْدُ'),'الحمد')
        self.assertEqual(aligner.normalizer('أَإِآ'),'ااا')
        self.assertEqual(aligner.normalizer('َۥـ'),'')

class CTCPathTests(unittest.TestCase):
    def test_whole_recording_requires_exact_native_word_coverage_and_clock(self):
        validate_recording_spans([[4,20,60],[7,100,140]],[4,7],150)
        for spans in ([[4,20,60]],[[4,20,60],[4,100,140]],
                      [[7,20,60],[4,100,140]],[[4,20,110],[7,100,140]],
                      [[4,20,60],[7,100,160]]):
            with self.subTest(spans=spans),self.assertRaises(ValueError):
                validate_recording_spans(spans,[4,7],150)

    def test_repeated_letters_need_separating_blank(self):
        emissions=np.log(np.array([[.01,.99],[.99,.01],[.01,.99]],dtype=np.float32))
        spans=viterbi(emissions,[1,1])
        self.assertEqual([(x[0],x[1]) for x in spans],[(0,1),(2,3)])
        with self.assertRaises(ValueError):viterbi(emissions[:1],[1,1])

    def test_path_follows_measured_labels_and_preserves_silence_gap(self):
        emissions=np.log(np.array([[.98,.01,.01],[.01,.98,.01],[.98,.01,.01],
                                   [.98,.01,.01],[.01,.01,.98],[.98,.01,.01]]))
        spans=viterbi(emissions,[1,2])
        self.assertEqual([(x[0],x[1]) for x in spans],[(1,2),(4,5)])

    def test_bad_inputs_and_quran_diacritics(self):
        self.assertEqual(normalize('ٱلْحَمْدُ'),'الحمد')
        with self.assertRaises(ValueError):viterbi(np.zeros((2,3)),[0])
        with self.assertRaises(ValueError):viterbi(np.array([[np.nan,0]]),[1])

    def test_introduction_and_closing_are_outside_mandatory_canonical_path(self):
        # Third label represents actual introductory/closing speech, not a
        # wildcard allowed between Quran words.
        emissions=np.full((8,4),.001,dtype=np.float32)
        for i,label in enumerate([3,3,1,0,2,0,3,3]):emissions[i,label]=.997
        spans=viterbi(np.log(emissions),[1,2],free_edges=True)
        self.assertEqual([(s[0],s[1]) for s in spans],[(2,3),(4,5)])

if __name__=='__main__':unittest.main()
