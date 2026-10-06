"""Install the exact complete original PDF; never OCR or rebuild Quran artwork."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DIGEST = '5c4297de1fb6b654f641eed33242408d89432cbecf8a96ff5d297cb45fea7f07'
SIZE = 243520529
OFFICIAL = 'https://qurancomplex.gov.sa/wp-content/uploads/isdarat/hafs/standard39-2.pdf'
MIRROR = 'https://cdn.quran.ws/KFGQPC/resources/quran-hafs/standard39-2/standard39-2.pdf'

def verify(path):
    if path.stat().st_size != SIZE:
        raise ValueError('Original PDF size differs')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != DIGEST:
        raise ValueError('Original PDF SHA256 differs')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'ios/Athar')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    destination = args.output / 'king-fahd-standard39-2.pdf'
    temporary = destination.with_suffix('.download')
    try:
        if args.source:
            verify(args.source)
            shutil.copyfile(args.source, temporary)
        elif destination.exists():
            verify(destination)
            print('Verified exact original PDF already installed')
            return
        else:
            with urllib.request.urlopen(MIRROR, timeout=90) as response, temporary.open('wb') as stream:
                shutil.copyfileobj(response, stream)
        verify(temporary)
        temporary.replace(destination)
        print(json.dumps({'file': str(destination), 'sha256': DIGEST, 'bytes': SIZE,
                          'officialSource': OFFICIAL, 'transportMirror': MIRROR}))
    finally:
        temporary.unlink(missing_ok=True)

if __name__ == '__main__':
    main()
