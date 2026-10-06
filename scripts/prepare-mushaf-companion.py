#!/usr/bin/env python3
"""Install a pinned original V2 companion for internal native visual review.
Release approval is blocked pending explicit common-font and layout rights.
No fonts are redistributed as standalone repository assets.
"""
import hashlib
from pathlib import Path
import urllib.request
ROOT = Path(__file__).resolve().parents[1]
URL = 'https://raw.githubusercontent.com/nuqayah/qpc-fonts/8a4f39d563ea69c994416a1692827e38156c548d/mushaf-v2/QCF2BSML.ttf'
HASH = '457cd1bf2174e9c10b31eab25bc5eda20c12abbafe5f47bdea473c64036f411e'
file = ROOT / 'ios/Athar/Fonts/QCF2BSML.ttf'
file.parent.mkdir(parents=True, exist_ok=True)
data = file.read_bytes() if file.exists() else urllib.request.urlopen(URL, timeout=45).read(1_000_001)
if len(data) != 327564 or hashlib.sha256(data).hexdigest() != HASH:
    raise SystemExit('Original V2 companion integrity failure; no font fallback installed')
file.write_bytes(data)
print('Verified original QCF2BSML 5.10 for internal review; release rights still pending')
