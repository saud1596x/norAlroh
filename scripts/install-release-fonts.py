"""Install exactly the reviewed font binaries from a private build secret.
Never print signed URLs or distribute this archive in the source delivery.
"""
import os,json,hashlib,urllib.request,zipfile,io
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];config=json.loads((ROOT/'release/config.json').read_text())
rights=config.get('fontDistributionRightsDocument')
if not rights or not (ROOT/rights).is_file():raise SystemExit('Document font distribution rights in release/config.json before installing release resources.')
path=os.environ.get('MUSHAF_FONT_ARCHIVE_PATH');address=os.environ.get('MUSHAF_FONT_ARCHIVE_URL')
if path:raw=Path(path).read_bytes()
elif address and address.startswith('https://'):
 try:
  with urllib.request.urlopen(address,timeout=120)as response:raw=response.read(250_000_001)
 except Exception:raise SystemExit('Private font archive could not be downloaded. Check the provider secret without sharing it in chat.')from None
else:raise SystemExit('Set MUSHAF_FONT_ARCHIVE_PATH or private HTTPS secret MUSHAF_FONT_ARCHIVE_URL in the build provider.')
if len(raw)>250_000_000:raise SystemExit('Font archive exceeds 250 MB.')
hashes=json.loads((ROOT/'ios/Athar/quran-resource-hashes.json').read_text());expected={k:v for k,v in hashes.items()if k.startswith('QCF')and k.endswith('.ttf')}
try:
 archive=zipfile.ZipFile(io.BytesIO(raw));files={}
 for info in archive.infolist():
  name=Path(info.filename).name
  if name not in expected:continue
  if name in files or info.file_size>8_000_000:raise ValueError('Duplicate or oversized font.')
  data=archive.read(info)
  if hashlib.sha256(data).hexdigest()!=expected[name]:raise ValueError('Font binary differs from reviewed hash.')
  files[name]=data
 if set(files)!=set(expected):raise ValueError('Archive must contain all 47 page fonts and the header font.')
except Exception:raise SystemExit('Private archive failed format/completeness/hash validation. No fonts were installed.')from None
folder=ROOT/'ios/Athar/Fonts';folder.mkdir(exist_ok=True)
for name,data in files.items():(folder/name).write_bytes(data)
print('Installed and verified 48 licensed local mushaf font resources.')
