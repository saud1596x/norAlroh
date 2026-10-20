"""Log a probe while preserving its exit code, then enforce complete evidence."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from validate_result import validate_result


def run_probe(output_dir, expected_commit, command):
    output_dir.mkdir(parents=True, exist_ok=True)
    # A prior complete report must never make a new, broken run appear green.
    for name in ('actual-source.json', 'source.txt', 'validation.json', 'execution.json'):
        (output_dir / name).unlink(missing_ok=True)
    start = time.monotonic()
    receipt = {'sourceCommit': expected_commit, 'status': 'STARTED',
               'inferenceVerified': False, 'productionApproved': False}

    def save():
        (output_dir / 'execution.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')

    save()
    try:
        with (output_dir / 'process.txt').open('w', encoding='utf-8', newline='') as log:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, encoding='utf-8', errors='replace', bufsize=1)
            for line in process.stdout:
                log.write(line)
                log.flush()
                print(line, end='', flush=True)
            code = process.wait()
        receipt.update(exitCode=code, elapsedSeconds=time.monotonic() - start)
        if code:
            receipt['status'] = 'PRODUCER_FAILED_INFERENCE_NOT_VERIFIED'
            save()
            return code if 0 < code <= 255 else 1
        result = validate_result(output_dir, expected_commit)
        (output_dir / 'validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        receipt.update(status='VERIFIED_SCREENING_EXECUTION_ONLY', inferenceVerified=True)
        save()
        print('SOURCE_SCREENING_EVIDENCE_VALIDATED ' + json.dumps(result), flush=True)
        return 0
    except Exception as error:
        receipt.update(status='FAILED_INFERENCE_NOT_VERIFIED', errorType=type(error).__name__,
                       elapsedSeconds=time.monotonic() - start)
        save()
        print('SOURCE_SCREENING_REJECTED: ' + str(error), file=sys.stderr, flush=True)
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A probe command is required')
    return run_probe(args.output_dir, args.expected_commit, command)


if __name__ == '__main__':
    raise SystemExit(main())
