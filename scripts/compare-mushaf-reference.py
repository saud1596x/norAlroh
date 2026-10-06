"""Compare actual page captures with uniform scaling only; never grants approval.

Paper/ink colors are removed before an edge-tolerant difference map is made.
The input crops and scale are recorded, so a comparison cannot silently warp
one page until it resembles another. Requires Pillow, NumPy and SciPy.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageOps
from scipy.ndimage import distance_transform_edt


def crop_rect(value):
    return tuple(int(x) for x in value.split(','))


def prepare(path, crop, width):
    original = Image.open(path).convert('RGB')
    box = crop or (0, 0, original.width, original.height)
    if len(box) != 4 or box[0] < 0 or box[1] < 0 or box[2] > original.width or box[3] > original.height or box[2] <= box[0] or box[3] <= box[1]:
        raise ValueError('Invalid source crop')
    image = original.crop(box)
    scale = width / image.width
    image = image.resize((width, round(image.height * scale)), Image.Resampling.LANCZOS)
    data = np.asarray(image).astype(float)
    # The four corners belong to paper, not glyphs. No OCR or Quran transcription.
    corners = np.concatenate([data[:4, :4].reshape(-1, 3), data[:4, -4:].reshape(-1, 3),
                              data[-4:, :4].reshape(-1, 3), data[-4:, -4:].reshape(-1, 3)])
    paper = np.median(corners, axis=0)
    coverage = np.max(np.abs(data - paper), axis=2) / max(32, np.max(np.maximum(paper, 255 - paper)))
    return coverage > 0.08, {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'crop': box, 'uniformScale': scale, 'resultSize': image.size}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--render', type=Path, required=True)
    p.add_argument('--reference-crop', type=crop_rect)
    p.add_argument('--render-crop', type=crop_rect)
    p.add_argument('--width', type=int, default=900)
    p.add_argument('--edge-tolerance', type=int, default=2)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    if not 100 <= args.width <= 3000 or not 0 <= args.edge_tolerance <= 8:
        p.error('Invalid comparison dimensions or edge tolerance')
    a, ar = prepare(args.reference, args.reference_crop, args.width)
    b, br = prepare(args.render, args.render_crop, args.width)
    height = max(a.shape[0], b.shape[0])
    a = np.pad(a, ((0, height - a.shape[0]), (0, 0)))
    b = np.pad(b, ((0, height - b.shape[0]), (0, 0)))
    only_a = a & (distance_transform_edt(~b) > args.edge_tolerance)
    only_b = b & (distance_transform_edt(~a) > args.edge_tolerance)
    common = (a | b) & ~only_a & ~only_b
    overlay = np.full((height, args.width, 3), 255, dtype=np.uint8)
    overlay[common] = (75, 75, 75)
    overlay[only_a] = (210, 45, 70)
    overlay[only_b] = (0, 155, 200)
    result = Image.new('RGB', (args.width * 3 + 40, height + 100), '#eeeeee')
    d = ImageDraw.Draw(result)
    for x, title, im in [(10, 'REFERENCE (COLOR REMOVED)', Image.fromarray(np.where(a, 0, 255).astype('uint8'))),
                         (args.width + 20, 'CURRENT APP - BEFORE', Image.fromarray(np.where(b, 0, 255).astype('uint8'))),
                         (args.width * 2 + 30, 'RED: REFERENCE / CYAN: CURRENT', Image.fromarray(overlay))]:
        d.text((x, 12), title, fill='black', font_size=16)
        result.paste(im, (x, 45))
    d.text((10, height + 60), 'Uniform width fit only. Different page heights remain visible. No automatic approval.', fill='black', font_size=16)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.output)
    report = {'status': 'COMPARISON_ONLY_NOT_APPROVAL', 'reference': ar, 'render': br,
        'edgeTolerancePixels': args.edge_tolerance, 'geometryTransform': 'uniform width fit; top aligned; no vertical stretch, registration or per-line warping',
        'warning': 'Inspect glyphs, marks, basmala, headers, markers, baselines and margins separately. No aggregate similarity score.'}
    args.output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'status': report['status']}))


if __name__ == '__main__':
    main()
