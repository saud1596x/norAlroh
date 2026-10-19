"""Canonical setup failures cannot count as acoustic rejection evidence."""
import json
import os
from pathlib import Path
import subprocess
import sys

import numpy as np
import pytest

from ctc import Aligner, AlignmentSetupError
from verify_catalog import align_windows


def test_utf8_arabic_labels_survive_a_child_without_utf8_mode(tmp_path):
    path = tmp_path / 'vocab.json'
    source = {'<pad>': 0, '|': 1, 'ب': 2, 'س': 3, 'م': 4}
    path.write_text(json.dumps(source, ensure_ascii=False), encoding='utf-8')
    # The actual Windows default was cp1256: a UTF-8 parent does not propagate
    # its -X flag to sys.executable children. Exercise that boundary explicitly.
    script = """
import sys
from ctc import read_vocabulary
from quran_ctc import QuranAligner
value = read_vocabulary(sys.argv[1])
assert len(value) == 5 and value[chr(0x628)] == 2
a = QuranAligner.__new__(QuranAligner)
a.vocab = value
labels, owners, expected = a.canonical_labels([(7, ''.join(map(chr,[0x628,0x633,0x645])))])
assert labels == [2,3,4] and owners == [7,7,7]
"""
    environment = dict(os.environ, PYTHONUTF8='0')
    environment['PYTHONPATH'] = str(Path(__file__).resolve().parent)
    result = subprocess.run([sys.executable, '-X', 'utf8=0', '-c', script, str(path)],
                            env=environment, capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr


def test_unknown_canonical_setup_is_not_a_successful_silence_rejection():
    aligner = Aligner.__new__(Aligner)
    aligner.vocab = {'<pad>': 0, '|': 1, 'ق': 2}
    with pytest.raises(AlignmentSetupError, match='Unknown canonical character'):
        aligner.align(np.zeros(16000), [(1, 'قل')])


def test_setup_error_aborts_ayah_audit_without_a_rejected_reciter_checkpoint():
    aligner = Aligner.__new__(Aligner)
    aligner.vocab = {'<pad>': 0, '|': 1, 'ق': 2}
    record, saves = {}, []
    with pytest.raises(AlignmentSetupError):
        align_windows(aligner, np.ones(16000), [[1, 0, 1000]], {1: [(1, 'قل')]},
                      record, lambda: saves.append(True))
    assert not saves and not record['ayahResults']
