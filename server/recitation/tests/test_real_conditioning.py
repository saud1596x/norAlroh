"""Explicit real public reference + injected DC fault, not natural learner audio."""
import hashlib
import json
import os
from pathlib import Path
import numpy as np
import pytest
from noor_engine.inference import Recognizer
from noor_engine.corpus import Corpus


@pytest.mark.skipif(not os.getenv('NOOR_REAL_MODEL_PATH'), reason='Requires pinned actual model and public fixtures')
def test_actual_quiet_reference_with_dc_fault_recovers_without_progress_on_flatline():
    from faster_whisper.audio import decode_audio
    root = Path(__file__).resolve().parents[3]
    source = next(s for s in json.loads((root/'tools/RecitationEngineProbe/fixtures/sources.json').read_text())
                  if s['file'] == '112001.mp3')
    path = Path(os.environ['NOOR_PUBLIC_FIXTURES'])/source['file']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == source['sha256']
    original = decode_audio(str(path), sampling_rate=16000)*np.float32(.03)
    fault = original + np.float32(.15)
    before = fault.copy()
    model = Recognizer(Path(os.environ['NOOR_REAL_MODEL_PATH']), device=os.getenv('NOOR_TEST_DEVICE', 'cpu'))
    model.load()
    plain = model._decode(original)
    recovered = model._decode(fault)
    assert np.array_equal(fault, before)
    assert [w['text'] for w in recovered['words']] == [w['text'] for w in plain['words']]
    corpus = Corpus(root)
    assert any(e['verse'] == '112:1' for e in corpus.align(recovered['words']))
    assert not model._decode(np.full(64000, .15, dtype=np.float32))['words']
