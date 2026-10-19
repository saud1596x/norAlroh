"""Typecheck the actual acoustic worker against Apple's SDK before asset builds.

No model weights, package downloads, credentials, generated stubs, or inference.
This is an API/type preflight, never evidence of acoustic or device quality.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CORE = 'ios/Athar/QuranIndependentCTC.swift'
SOURCES = [
    'tools/RecitationEngineProbe/Sources/RecitationAlignment/QuranWordAlignment.swift',
    'tools/RecitationEngineProbe/Sources/RecitationAlignment/QuranIndependentAgreement.swift',
    'tools/RecitationEngineProbe/Sources/RecitationCapture/QuranPCMWriter.swift',
    'tools/RecitationEngineProbe/Sources/RecitationSessions/QuranIndependentObservation.swift',
    CORE,
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='List actual inputs; does not typecheck')
    parser.add_argument('--compare-prior', help='Also require a known prior CoreML API failure to be detected')
    args = parser.parse_args()
    inputs = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in SOURCES}
    if args.list:
        print(json.dumps({'sources': inputs, 'nativeTypecheck': 'NOT_RUN'})); return
    if sys.platform != 'darwin':
        raise RuntimeError('Actual Apple SDK typecheck requires the Mac build host')
    if args.compare_prior and not re.fullmatch(r'[0-9a-f]{7,40}', args.compare_prior):
        raise ValueError('Expected a literal prior commit SHA')
    out = ROOT/'release/recitation-core-preflight'; out.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    architecture = platform.machine()
    if architecture not in ('arm64', 'x86_64'):
        raise ValueError('Unsupported Apple build architecture')
    common = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-typecheck', '-parse-as-library',
              '-swift-version', '5', '-target', architecture+'-apple-ios17.0-simulator',
              '-sdk', sdk, '-module-name', 'NoorAcousticCorePreflight', '-DNOOR_ACCEPTANCE_TESTING']
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    result = subprocess.run(common+[str(ROOT/name) for name in SOURCES], cwd=ROOT,
                            capture_output=True, text=True, timeout=180)
    (out/'current.txt').write_text(result.stdout+result.stderr, encoding='utf-8')
    print(result.stdout+result.stderr, end='')
    report = {'source': source, 'sourceHashes': inputs, 'sdk': sdk, 'architecture': architecture,
              'swiftVersion': '5', 'deploymentTarget': 'iOS17 Simulator', 'typecheckExit': result.returncode,
              'scope': 'ACTUAL_SOURCE_API_TYPECHECK_ONLY_NOT_NATIVE_EXECUTION_OR_ACCURACY'}
    (out/'report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    if result.returncode:
        raise SystemExit(result.returncode)
    if args.compare_prior:
        original = subprocess.check_output(['git', 'show', args.compare_prior+':'+CORE], cwd=ROOT)
        with tempfile.TemporaryDirectory(prefix='noor-core-typecheck-') as folder:
            prior = Path(folder)/'QuranIndependentCTC.swift'; prior.write_bytes(original)
            old = subprocess.run(common+[str(ROOT/name) for name in SOURCES[:-1]]+[str(prior)], cwd=ROOT,
                                 capture_output=True, text=True, timeout=180)
        (out/'prior.txt').write_text(old.stdout+old.stderr, encoding='utf-8')
        detected = old.returncode != 0 and "expression is 'async' but is not marked with 'await'" in old.stderr
        report['priorFailureControl'] = {'source': args.compare_prior,
            'workerSHA256': hashlib.sha256(original).hexdigest(), 'typecheckExit': old.returncode,
            'knownAsyncOverloadErrorDetected': detected}
        (out/'report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
        if not detected:
            raise RuntimeError('Known prior failure was not detected; retain original output for diagnosis')
    print('NOOR_ACOUSTIC_CORE_TYPECHECK_PASSED (types only; no recognition/device quality claim)')


if __name__ == '__main__':
    main()
