"""Make review sheets ONLY from exported production UIKit screenshots.

This never draws Quran text, reshapes a word, or manufactures an app screen.
The source images and manifest remain available beside the overview sheets.
"""
import argparse
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

parser = argparse.ArgumentParser()
parser.add_argument('attachments', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
manifest = json.loads((args.attachments / 'manifest.json').read_text())
pages = {}
for test in manifest:
    for attachment in test['attachments']:
        match = re.search(r'QCF-V2-shaped-page-(\d{3})(?:_|\.)', attachment['suggestedHumanReadableName'])
        if match:
            number = int(match[1])
            if number in pages:
                raise ValueError(f'Duplicate native page capture: {number}')
            pages[number] = attachment
if set(pages) != set(range(1, 605)):
    raise ValueError(f'Incomplete actual page gallery: {len(pages)}/604')
args.output.mkdir(parents=True, exist_ok=True)
for offset in range(0, 604, 48):
    sheet = Image.new('RGB', (8 * 170, 6 * 305), '#eee9df')
    draw = ImageDraw.Draw(sheet)
    for slot, number in enumerate(range(offset + 1, min(offset + 49, 605))):
        attachment = pages[number]
        with Image.open(args.attachments / attachment['exportedFileName']) as source:
            thumbnail = ImageOps.contain(source.convert('RGB'), (160, 274))
            x, y = slot % 8 * 170, slot // 8 * 305
            sheet.paste(thumbnail, (x + (170 - thumbnail.width) // 2, y + 4))
        draw.text((x + 8, y + 283), f'Page {number:03d}', fill='#493522')
    sheet.save(args.output / f'native-pages-{offset + 1:03d}-{min(offset + 48, 604):03d}.jpg', quality=95)
(args.output / 'capture-index.json').write_text(json.dumps({
    'pageCount': len(pages), 'renderer': 'OriginalMushafCanvas / UIKit / CoreText',
    'source': str(args.attachments), 'pages': pages,
    'acceptance': 'Actual native captures; requires human visual review.',
}, indent=2))
print('Exported 13 contact sheets from all 604 actual native page captures.')
