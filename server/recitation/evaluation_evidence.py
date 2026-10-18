"""Development evidence only: interrupted measurements cannot become a pass."""
import json
from pathlib import Path


def save_progress(path, source_hashes, expected_cases, cases, *, complete=False):
    if (type(expected_cases) is not int or expected_cases < 1
            or len(cases) > expected_cases or (complete and len(cases) != expected_cases)
            or len({case['case'] for case in cases}) != len(cases)):
        raise ValueError('Incomplete, duplicate or unexpected evaluation cases')
    document = {'status': 'COMPLETED_DIAGNOSTIC_NOT_LEARNER_ACCEPTANCE' if complete else 'INCOMPLETE',
                'source_hashes': source_hashes, 'expected_cases': expected_cases,
                'completed_cases': len(cases), 'cases': cases,
                'limits': 'Public reference diagnostic only; not unseen learner, iPhone or Tajweed acceptance'}
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.pending')
    temporary.write_text(json.dumps(document, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    temporary.replace(path)
