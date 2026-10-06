"""Require the current text engine's native interaction and reference evidence.
Earlier PDF approval cannot authorize this renderer.
"""
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def main():
    path = ROOT / 'release/interactive-mushaf-review.json'
    if not path.is_file():
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: shaped reader review is missing')
    review = json.loads(path.read_text())
    if review.get('publicationApproved') is not True or review.get('status') != 'APPROVED_MATCHING_REFERENCE':
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: current text engine awaits actual native and reference review')
    for field in ['all604DataValidated','all604NativeBoundsValidated','all604WordHitRegionsValidated','unicodeCorpusValidated','zoomPanSelectionVerified','offlineReadingVerified','rightsCleared']:
        if review.get(field) is not True:
            raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: ' + field)
    if not {1,2,3,151,572,598,604}.issubset(set(review.get('referencePagesVisuallyCompared',[]))):
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: supplied reference comparisons incomplete')
    if not review.get('actualAppVideo') or not review.get('actualAppScreenshots') or review.get('notYetVerified'):
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: actual native evidence or remaining checks incomplete')
    required = {'ios/Athar/InteractiveMushafCanvas.swift','ios/Athar/InteractiveMushafReader.swift','ios/Athar/MushafReader.swift','ios/Athar/qpc-v2-line-layout.json','release/qcf-v2-manifest.json'}
    hashes = review.get('approvedSourceHashes',{})
    if not required.issubset(hashes):
        raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: reviewed source hashes incomplete')
    for name, expected in hashes.items():
        file = ROOT / name
        if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            raise SystemExit('MUSHAF_PUBLICATION_BLOCKED: reviewed source changed: ' + name)
    print('CURRENT_SHAPED_MUSHAF_NATIVE_AND_VISUAL_REVIEW_VERIFIED')

if __name__ == '__main__':
    main()
