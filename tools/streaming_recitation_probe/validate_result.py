"""Reject missing, partial, stale or invalid evidence even if a child exits zero."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

from probe_contract import (ARCHIVE_SHA, COMPLETE, CONFIG_SHA, END_MARKER,
                            EXPECTED_CASE_COUNT, MARKER, MODEL, REVISION, SCOPE,
                            expected_cases)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive_number(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def validate_result(output_dir, expected_commit):
    output_dir = Path(output_dir)
    require(re.fullmatch(r'[0-9a-f]{40}', expected_commit) is not None, 'Expected a full source commit')
    report_path = output_dir / 'actual-source.json'
    require(report_path.is_file(), 'Missing actual-source.json; inference NOT verified')
    report_bytes = report_path.read_bytes()
    require(0 < len(report_bytes) <= 1_000_000, 'Invalid report size')
    report = json.loads(report_bytes)
    require(type(report) is dict and report.get('schemaVersion') == 1, 'Unknown evidence schema')
    for key, value in {'sourceModel': MODEL, 'revision': REVISION,
                       'archiveSHA256': ARCHIVE_SHA, 'configurationSHA256': CONFIG_SHA,
                       'scope': SCOPE, 'status': COMPLETE,
                       'sourceCommit': expected_commit}.items():
        require(report.get(key) == value, 'Evidence mismatch: ' + key)
    for key in ('appIntegrated', 'productionApproved', 'expectedPassageInput'):
        require(report.get(key) is False, 'Screening must not claim acceptance: ' + key)
    require(report.get('inferenceCompleted') is True, 'Inference did not complete')
    require(report.get('expectedCaseCount') == EXPECTED_CASE_COUNT, 'Wrong expected inference count')
    require(report.get('inferenceCaseCount') == EXPECTED_CASE_COUNT, 'Wrong completed inference count')
    require(positive_number(report.get('modelLoadSeconds')), 'Invalid model load measurement')
    require(isinstance(report.get('torchVersion'), str) and report['torchVersion'], 'Missing actual runtime')
    require(report.get('sourceConfiguration') == 'FP32/offline/full-context/CTC-head/no-RNNT-LM',
            'Unexpected inference mode')
    source = output_dir / 'source.txt'
    require(source.is_file() and source.read_text(encoding='utf-8').strip() == expected_commit,
            'Missing or stale source receipt')
    cases = report.get('cases')
    require(type(cases) is list and len(cases) == EXPECTED_CASE_COUNT, 'Expected exactly 26 inference cases')
    expected = expected_cases()
    for row, identity in zip(cases, expected):
        require(type(row) is dict, 'Invalid inference row')
        require((row.get('file'), row.get('kind'), row.get('sourceMP3SHA256')) == identity,
                'Missing, duplicate or out-of-order input case')
        require(row.get('inferenceCompleted') is True, 'An input did not reach inference')
        require(type(row.get('sourceFrames')) is int and 400 <= row['sourceFrames'] <= 256000,
                'Invalid actual audio frame count')
        if row['kind'] == 'public-first-two-seconds':
            require(row['sourceFrames'] == 32000, 'Prefix probe must use exactly two seconds')
        if row['file'] in ('silence', 'noise'):
            require(row['sourceFrames'] == 16000, 'Negative controls must use exactly one second')
        require(isinstance(row.get('sourceFloatSHA256'), str) and
                re.fullmatch(r'[0-9a-f]{64}', row['sourceFloatSHA256']) is not None,
                'Missing source PCM hash')
        require(type(row.get('encoderFrames')) is int and 0 < row['encoderFrames'] <= row['sourceFrames'],
                'No actual encoder output')
        require(positive_number(row.get('seconds')), 'Invalid inference duration')
        require(type(row.get('rawTranscript')) is str, 'Missing raw transcript (empty is allowed)')
        ids = row.get('rawTokenIDs')
        require(type(ids) is list and all(type(token) is int and 0 <= token < 1024 for token in ids),
                'Invalid CTC token output')
        require(len(ids) <= row['encoderFrames'], 'More collapsed tokens than encoder frames')
    log = output_dir / 'process.txt'
    require(log.is_file(), 'Missing producer log')
    lines = log.read_text(encoding='utf-8').splitlines()
    logged = [json.loads(line[len(MARKER):]) for line in lines if line.startswith(MARKER)]
    require(logged == cases, 'Producer log does not contain the same 26 actual inference rows')
    require(lines.count(END_MARKER) == 1, 'Missing or duplicate completion marker')
    return {'status': 'VERIFIED_SCREENING_EXECUTION_ONLY', 'inferenceCaseCount': len(cases),
            'sourceCommit': expected_commit, 'reportSHA256': hashlib.sha256(report_bytes).hexdigest(),
            'productionApproved': False, 'learnerAccuracyVerified': False,
            'streamingVerified': False, 'iPhoneAcceptance': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--expected-commit', required=True)
    args = parser.parse_args()
    print(json.dumps(validate_result(args.output_dir, args.expected_commit), ensure_ascii=False))


if __name__ == '__main__':
    main()
