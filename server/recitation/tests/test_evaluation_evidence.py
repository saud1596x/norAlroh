"""Interrupted evaluator evidence, not acoustic success fixtures."""
import json
from pathlib import Path
from unittest.mock import patch
import pytest
from evaluation_evidence import save_progress


def test_partial_or_duplicate_cases_cannot_certify_a_completed_measurement(tmp_path):
    file = tmp_path/'progress.json'
    cases = [{'case':'actual-first', 'raw_source_observations':[{'text':'observed'}]}]
    save_progress(file, {'source':'digest'}, 2, cases)
    actual = json.loads(file.read_text())
    assert actual['status'] == 'INCOMPLETE' and actual['completed_cases'] == 1
    assert actual['cases'] == cases
    with pytest.raises(ValueError): save_progress(file, {}, 2, cases, complete=True)
    with pytest.raises(ValueError): save_progress(file, {}, 2, cases+cases, complete=True)
    save_progress(file, {}, 2, cases+[{'case':'actual-second'}], complete=True)
    assert json.loads(file.read_text())['status'] == 'COMPLETED_DIAGNOSTIC_NOT_LEARNER_ACCEPTANCE'


def test_failed_atomic_replacement_keeps_previous_source_evidence(tmp_path):
    file = tmp_path/'progress.json'
    save_progress(file, {'source':'digest'}, 2, [{'case':'first'}])
    before = file.read_bytes()
    with patch.object(Path, 'replace', side_effect=OSError('Injected local write failure')):
        with pytest.raises(OSError): save_progress(file, {}, 2, [{'case':'first'},{'case':'second'}], complete=True)
    assert file.read_bytes() == before
