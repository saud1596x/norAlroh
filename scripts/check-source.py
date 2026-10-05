"""Parse source with the real Swift compiler. This is not an iOS build or type check."""
import argparse, ast, datetime, hashlib, json, plistlib, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--swiftc', required=True, type=Path)
args = parser.parse_args()
issues = []
hashes = {}

def record(path):
    hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()

def attempt(label, action):
    try:
        action()
    except Exception as error:
        issues.append({'check': label, 'error': str(error), 'diagnostics': getattr(error, 'stderr', '')[-6000:]})

swift_files = sorted((ROOT / 'ios').rglob('*.swift'))
for path in swift_files:
    record(path)
    attempt(str(path.relative_to(ROOT)), lambda path=path: subprocess.run(
        [str(args.swiftc), '-frontend', '-parse', '-swift-version', '5', str(path)],
        check=True, capture_output=True, text=True))

for path in sorted((ROOT / 'scripts').glob('*.py')):
    record(path)
    attempt(str(path.relative_to(ROOT)), lambda path=path: ast.parse(path.read_text(), filename=str(path)))

for path in sorted((ROOT / 'ios').rglob('*')):
    if path.suffix in ['.plist', '.xcprivacy']:
        record(path)
        attempt(str(path.relative_to(ROOT)), lambda path=path: plistlib.loads(path.read_bytes()))
    elif path.suffix == '.json':
        record(path)
        attempt(str(path.relative_to(ROOT)), lambda path=path: json.loads(path.read_text()))

for path in sorted((ROOT / 'scripts').glob('*.sh')):
    record(path)
    attempt(str(path.relative_to(ROOT)), lambda path=path: subprocess.run(
        ['bash', '-n', str(path)], check=True, capture_output=True, text=True))

version = subprocess.run([str(args.swiftc), '--version'], check=True, capture_output=True, text=True).stdout.strip()
report = {'status': 'PASS' if not issues else 'FAIL', 'testedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'swiftSyntaxFiles': len(swift_files), 'swiftCompiler': version, 'swiftCompilerParse': 'PASS' if not issues else 'SEE_ISSUES',
          'issues': issues, 'sourceHashes': hashes, 'nativeCompilation': 'NOT_RUN',
          'meaning': 'Real compiler syntax parsing, Python AST, plist/JSON parsing and bash syntax. SwiftUI/UIKit type checking, native build, UI, microphone and release execution are not performed.'}
(ROOT / 'release/source-checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps({key: value for key, value in report.items() if key != 'sourceHashes'}, ensure_ascii=False, indent=2))
sys.exit(bool(issues))
