"""Export original XCTest PNGs through authenticated CI logs as well as artifacts.

No regenerated images, cropping, UI state injection, credentials or user audio.
This is a bounded transport for viewing the actual test attachments when the
desktop's artifact download cannot authenticate. SHA256 protects reconstruction.
"""
import base64, hashlib, json, subprocess, sys
from pathlib import Path

bundle = Path(sys.argv[1]); out = bundle.parent / 'screenshots'
video_status = bundle.parent / 'video-status.json'
if video_status.exists(): print('NOOR_ACTUAL_VIDEO_STATUS ' + video_status.read_text().strip(), flush=True)
try:
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle),
                    '--output-path', str(out)], check=True, timeout=45)
    candidates = sorted((p for p in out.rglob('*.png') if 20_000 < p.stat().st_size <= 1_500_000), key=lambda p:p.name)[:4]
    for p in candidates:
        b = p.read_bytes()
        print('NOOR_SCREENSHOT_BEGIN ' + json.dumps({'name':p.name, 'bytes':len(b), 'sha256':hashlib.sha256(b).hexdigest()}),flush=True)
        encoded = base64.b64encode(b).decode()
        for i in range(0, len(encoded), 2048): print('NOOR_SCREENSHOT_DATA ' + encoded[i:i + 2048])
        print('NOOR_SCREENSHOT_END',flush=True)
    print('NOOR_SCREENSHOT_EXPORT ' + json.dumps({'count':len(candidates),'scope':'Actual native XCTest attachments; not physical-device evidence'}),flush=True)
except (subprocess.SubprocessError, OSError) as error:
    print('NOOR_SCREENSHOT_EXPORT_UNAVAILABLE ' + type(error).__name__,flush=True)
