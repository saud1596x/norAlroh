"""Reject obsolete literal XCTest selectors before paying for native CI.

Static discovery is a preflight, never proof that tests ran. Actual xcresult
counts and failures remain required. Test bundles include their linked probe
test sources from project.yml, and files may contain multiple test classes.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLASS = re.compile(r'(?m)^\s*(?:@\w+(?:\([^\n]*\))?\s+)*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b')
METHOD = re.compile(r'\bfunc\s+(test\w+)\s*\(')
SELECTOR = re.compile(r'-(?:only|skip)-testing:(Athar(?:UI)?Tests)(?:/(\w+)(?:/(\w+))?)?')


def declarations(text):
    # Declarations in comments cannot make a removed test look executable.
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    classes = list(CLASS.finditer(text))
    return {item[1]: set(METHOD.findall(text[item.end():classes[i+1].start() if i+1 < len(classes) else len(text)]))
            for i, item in enumerate(classes)}


def inventory(root=ROOT):
    result = {'AtharTests': {}, 'AtharUITests': {}}
    for bundle in result:
        files = list((root / 'ios' / bundle).glob('*.swift'))
        if bundle == 'AtharTests':
            spec = (root / 'ios/project.yml').read_text(encoding='utf-8')
            for name in re.findall(r'path:\s*(\.\./tools/[^\s]+Tests\.swift)', spec):
                files.append((root / 'ios' / name).resolve())
        for path in files:
            result[bundle].update(declarations(path.read_text(encoding='utf-8')))
    return result


def validate(text, suites, filename):
    checked = 0
    for match in SELECTOR.finditer(text):
        bundle, suite, method = match.groups()
        known = suites[bundle]
        if not known or (suite and suite not in known) or (method and method not in known[suite]):
            line = text[:match.start()].count('\n') + 1
            raise ValueError(f'{filename}:{line}: missing native test {match[0]}')
        checked += 1
    return checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scripts', nargs='*', type=Path)
    args = parser.parse_args()
    paths = args.scripts or sorted((ROOT / 'scripts').glob('*.sh'))
    suites = inventory()
    checked = 0
    for path in paths:
        checked += validate(path.read_text(encoding='utf-8'), suites, str(path))
    print(json.dumps({'literalSelectorsVerified': checked,
                      'scope': 'STATIC_PREFLIGHT_ONLY_NOT_TEST_EXECUTION'}))


if __name__ == '__main__':
    main()
