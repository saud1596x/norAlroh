"""Block publication until the matching 604-page package has human visual approval."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
receipt = ROOT / 'release/mushaf-artwork-readiness.json'
manifest = ROOT / 'ios/Athar/mushaf-artwork-manifest.json'


def main():
    if not receipt.is_file() or not manifest.is_file():
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: matching artwork package and review receipt are required')
    review = json.loads(receipt.read_text())
    if review.get('status') != 'APPROVED_MATCHING_REFERENCE' or review.get('releaseApproved') is not True:
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: reference appearance is not approved')
    if review.get('manifestSHA256') != hashlib.sha256(manifest.read_bytes()).hexdigest():
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: review does not belong to this artwork package')
    data = json.loads(manifest.read_text())
    if data.get('reviewStatus') != 'APPROVED_MATCHING_REFERENCE' or [p.get('number') for p in data.get('pages', [])] != list(range(1, 605)):
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: incomplete or unapproved package')
    if not {1, 2, 3, 151, 604}.issubset(set(review.get('referencePagesVisuallyCompared', []))):
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: required references have not been compared')
    if review.get('all604DataValidated') is not True or review.get('nativeAfterEvidence') is None or review.get('rightsCleared') is not True:
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: data, native evidence or rights are incomplete')
    for page in data['pages']:
        expected = f'mushaf-artwork-{page["number"]:03d}.pdf'
        if page.get('file') != expected:
            raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: unexpected artwork filename')
        path = ROOT / 'ios/Athar' / expected
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != page.get('sha256'):
            raise SystemExit(f'MUSHAF_PUBLICATION_BLOCKED: page {page["number"]} missing or changed')
    print('MATCHING_MUSHAF_PACKAGE_AND_REVIEW_VERIFIED')


if __name__ == '__main__':
    main()
