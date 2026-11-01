"""Pure policy/numeric fixtures only: no model load, prediction or ASR claim."""
import copy
import hashlib
import math
import tempfile
from types import SimpleNamespace
import unittest
from pathlib import Path

import numpy as np
import compiled_fp32_probe as probe


class CompiledFP32PolicyTests(unittest.TestCase):
    def descriptor(self):
        files = {'quran-ctc.mlmodelc/model.mil': 'a' * 64,
                 'vocab.json': probe.VOCAB_SHA, 'NOTICE.txt': 'b' * 64}
        return {'schema': 1, 'revision': probe.REVISION, 'precision': 'float32',
                'compiler': 'Xcode fixture', 'sourceWeightsSHA256': probe.SOURCE_WEIGHTS_SHA,
                'convertedWeightsSHA256': probe.CONVERTED_WEIGHTS_SHA,
                'sourceSpecSHA256': probe.GRAPH_SHA, 'files': files,
                'verificationScope': probe.VERIFICATION_SCOPE}

    def test_descriptor_binds_exact_graph_precision_compiler_and_complete_inventory(self):
        document = self.descriptor()
        probe.validate_descriptor(document, document['files'], 'Xcode fixture')
        for field in ('revision', 'precision', 'compiler', 'sourceWeightsSHA256',
                      'convertedWeightsSHA256', 'sourceSpecSHA256', 'verificationScope'):
            changed = copy.deepcopy(document); changed[field] = 'changed'
            with self.subTest(field=field), self.assertRaises(ValueError):
                probe.validate_descriptor(changed, document['files'], 'Xcode fixture')
        changed = dict(document['files']); changed['unreviewed.bin'] = 'c' * 64
        with self.assertRaises(ValueError): probe.validate_descriptor(document, changed, 'Xcode fixture')
        changed = dict(document['files']); changed['vocab.json'] = 'c' * 64
        with self.assertRaises(ValueError): probe.validate_descriptor(document, changed, 'Xcode fixture')

    def test_descriptor_rejects_traversal_missing_model_and_boolean_schema(self):
        for bad in ('../escape', '/absolute', 'C:/absolute', 'quran-ctc.mlmodelc//bad', 'back\\slash'):
            document = self.descriptor(); document['files'][bad] = 'a' * 64
            with self.subTest(path=bad), self.assertRaises(ValueError):
                probe.validate_descriptor(document, document['files'], 'Xcode fixture')
        document = self.descriptor(); del document['files']['quran-ctc.mlmodelc/model.mil']
        with self.assertRaises(ValueError): probe.validate_descriptor(document, document['files'], 'Xcode fixture')
        document = self.descriptor(); document['schema'] = True
        with self.assertRaises(ValueError): probe.validate_descriptor(document, document['files'], 'Xcode fixture')

    def test_probe_pins_match_the_approved_app_preparer_not_compressed_candidate(self):
        import importlib
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
        approved = importlib.import_module('prepare-independent-ctc')
        self.assertEqual(probe.REVISION, approved.REVISION)
        self.assertEqual(probe.GRAPH_SHA, approved.PINS['Data/com.apple.CoreML/model.mlmodel'])
        self.assertEqual(probe.CONVERTED_WEIGHTS_SHA, approved.PINS['Data/com.apple.CoreML/weights/weight.bin'])
        self.assertEqual(probe.COMPUTES, ('CPU_ONLY', 'CPU_AND_GPU'))

    def test_inventory_rejects_content_drift_and_linked_assets(self):
        # Only tiny generated files exercise inventory safety, never a model.
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2] / 'release') as folder:
            root = Path(folder); (root / 'asset').write_bytes(b'original')
            first = probe.inventory(root)
            self.assertEqual(first['asset'], hashlib.sha256(b'original').hexdigest())
            (root / 'asset').write_bytes(b'changed')
            self.assertNotEqual(first, probe.inventory(root))
            try: (root / 'link').symlink_to(root / 'asset')
            except OSError: return  # Windows may deny symlink creation; other checks still run.
            with self.assertRaises(ValueError): probe.inventory(root)

    def test_conditioning_uses_sequential_double_math_and_preserves_raw_pcm(self):
        pcm = np.resize(np.array([.1234567, -.8, .00001, .4], dtype=np.float32), 400)
        original = pcm.tobytes(); total = 0.0
        for value in pcm: total += float(value)
        mean = total / len(pcm); variance = 0.0
        for value in pcm: variance += math.pow(float(value) - mean, 2)
        divisor = math.sqrt(variance / len(pcm) + 1e-7)
        expected = np.array([(float(value) - mean) / divisor for value in pcm], dtype=np.float32)[None]
        np.testing.assert_array_equal(probe.condition_pcm(pcm), expected)
        self.assertEqual(pcm.tobytes(), original)
        np.testing.assert_array_equal(probe.condition_pcm(np.zeros(400, dtype=np.float32)), np.zeros((1, 400), dtype=np.float32))

    def test_input_shape_range_precision_and_finiteness_are_not_repaired(self):
        for pcm in (np.zeros(399, dtype=np.float32), np.zeros(256001, dtype=np.float32),
                    np.zeros((1, 400), dtype=np.float32), np.zeros(400, dtype=np.float64),
                    np.full(400, np.nan, dtype=np.float32), np.full(400, 1.01, dtype=np.float32)):
            with self.subTest(shape=pcm.shape), self.assertRaises(ValueError): probe.validate_pcm(pcm)

    def test_logits_keep_the_native_400_320_frame_clock_and_float32(self):
        probe.validate_logits(np.zeros((1, 99, 56), dtype=np.float32), 32000)
        for values in (np.zeros((1, 100, 56), dtype=np.float32), np.zeros((99, 56), dtype=np.float32),
                       np.zeros((1, 99, 55), dtype=np.float32), np.zeros((1, 99, 56), dtype=np.float64),
                       np.full((1, 99, 56), np.inf, dtype=np.float32)):
            with self.subTest(shape=values.shape), self.assertRaises(ValueError): probe.validate_logits(values, 32000)

    def case(self):
        return {'id': 'policy-fixture', 'samples': 400, 'startFrame': 0, 'endFrame': 400,
                'rawPCM_SHA256': 'a' * 64, 'conditionedSHA256': 'b' * 64,
                'shape': [1, 1, 56], 'rawWords': ['ا'], 'frameLabels': [2],
                'words': [{'text': 'ا', 'startFrame': 0, 'endFrame': 320, 'meanPosterior': .9}]}

    def test_parity_rejects_source_clock_words_frame_and_posterior_drift(self):
        left = self.case(); posterior = np.array([[.05, .05, .9]], dtype=np.float64)
        probe.validate_parity(left, copy.deepcopy(left), posterior, posterior.copy())
        mutations = [('rawPCM_SHA256', 'c' * 64), ('conditionedSHA256', 'c' * 64),
                     ('samples', 401), ('startFrame', 1), ('endFrame', 401),
                     ('shape', [1, 2, 56]), ('rawWords', ['ب']), ('frameLabels', [1])]
        for key, value in mutations:
            right = copy.deepcopy(left); right[key] = value
            with self.subTest(field=key), self.assertRaises(ValueError):
                probe.validate_parity(left, right, posterior, posterior)
        for key, value in [('startFrame', False), ('shape', [True, 1, 56])]:
            a = copy.deepcopy(left); b = copy.deepcopy(left); a[key] = b[key] = value
            with self.subTest(boolean=key), self.assertRaises(ValueError): probe.validate_parity(a, b, posterior, posterior)
        right = copy.deepcopy(left); right['words'][0]['endFrame'] = 321
        with self.assertRaises(ValueError): probe.validate_parity(left, right, posterior, posterior)
        right = copy.deepcopy(left); right['words'][0]['meanPosterior'] = .8
        with self.assertRaises(ValueError): probe.validate_parity(left, right, posterior, posterior)
        with self.assertRaises(ValueError): probe.validate_parity(left, left, posterior, np.array([[.1, .1, .8]]))
        with self.assertRaises(ValueError): probe.validate_parity(left, left, posterior, np.full((1, 3), np.nan))

    def test_failed_profile_is_preserved_and_cannot_be_relabelled_as_comparison_success(self):
        import json
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2] / 'release') as folder:
            root = Path(folder)
            for name in ('CPU_ONLY', 'CPU_AND_GPU'):
                (root / name).mkdir()
                (root / name / 'profile.json').write_text(json.dumps({'status': 'FAILED', 'errors': ['actual load failed']}))
            original = (root / 'CPU_ONLY/profile.json').read_bytes()
            args = SimpleNamespace(baseline=root/'CPU_ONLY', candidate=root/'CPU_AND_GPU',
                                   expected_source='a'*40, output=root/'comparison.json')
            self.assertEqual(probe.compare(args), 1)
            self.assertEqual((root/'CPU_ONLY/profile.json').read_bytes(), original)
            result = json.loads(args.output.read_text(encoding='utf-8'))
            self.assertEqual(result['status'], 'FAILED'); self.assertTrue(result['errors'])
            with self.assertRaises(ValueError): probe.compare(args)

    def test_decoder_keeps_actual_repeats_blanks_and_word_clock(self):
        vocab = __import__('json').loads((Path(__file__).resolve().parents[2] / 'content-sources/independent-ctc-vocab.json').read_text(encoding='utf-8'))
        label = vocab['ا']; ids = [label, label, 0, label, vocab['|']]
        logits = np.full((1, len(ids), 56), -20, dtype=np.float32)
        for frame, symbol in enumerate(ids): logits[0, frame, symbol] = 20
        decoded, posterior = probe.decode_logits(logits, 1680, vocab)
        self.assertEqual(decoded['rawWords'], ['اا'])
        self.assertEqual(decoded['words'][0]['startFrame'], 0)
        self.assertEqual(decoded['words'][0]['endFrame'], 1280)
        self.assertEqual(len(decoded['frameLabels']), 5)
        self.assertTrue(np.isfinite(posterior).all())


if __name__ == '__main__': unittest.main()
