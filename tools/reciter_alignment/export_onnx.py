"""Local pinned-weight export for independent acoustic evaluation, not acceptance.

No expected Quran text enters the model. The exported model is a development
artifact, never a mobile download or an automatic replacement of the decoder.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import time

from quran_ctc import FILES, REVISION, verify_assets


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            sha.update(chunk)
    return sha.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--precision', choices=['float32', 'float16'], default='float32')
    args = parser.parse_args()
    verify_assets(args.model)
    args.output.mkdir(parents=True, exist_ok=True)
    output = args.output / 'quran-ctc.onnx'
    temporary = args.output / 'quran-ctc.pending.onnx'
    if any(p.exists() or p.is_symlink() for p in (output, temporary, args.output / 'export.json')):
        raise ValueError('Export destination already contains a model/receipt')
    size = (args.model / 'model.safetensors').stat().st_size
    projected_size = size if args.precision == 'float32' else size // 2 + 10_000_000
    if shutil.disk_usage(args.output).free < projected_size + 1_000_000_000:
        raise ValueError('Preserve one GB free disk beyond the exported model')
    import numpy as np
    import onnx
    import torch
    from transformers import Wav2Vec2ForCTC

    torch.set_num_threads(4)
    model = Wav2Vec2ForCTC.from_pretrained(str(args.model), local_files_only=True,
        use_safetensors=True, attn_implementation='eager').eval()
    if args.precision == 'float16':
        model.half()

    class Logits(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.acoustic_model = model

        def forward(self, input_values):
            values = input_values.to(dtype=next(self.acoustic_model.parameters()).dtype)
            return self.acoustic_model(values).logits.float()

    started = time.monotonic()
    # Artificial values only exercise graph conversion/shape parity. They are
    # never reported as speech, timing quality or real-acoustic acceptance.
    values = torch.from_numpy(np.random.default_rng(42).normal(0, .02, (1, 16000)).astype(np.float32))
    with torch.inference_mode():
        torch.onnx.export(Logits().eval(), values, str(temporary), opset_version=17,
            input_names=['input_values'], output_names=['logits'],
            dynamic_axes={'input_values': {0: 'batch', 1: 'samples'},
                          'logits': {0: 'batch', 1: 'frames'}},
            dynamo=False, external_data=False)
    onnx.checker.check_model(str(temporary))
    temporary.replace(output)
    receipt = {'schema': 1, 'sourceRevision': REVISION, 'sourceFiles': FILES,
        'sha256': digest(output), 'bytes': output.stat().st_size,
        'modelFile': output.name, 'opset': 17, 'precision': args.precision,
        'torchVersion': torch.__version__, 'onnxVersion': onnx.__version__,
        'seconds': round(time.monotonic() - started, 3),
        'purpose': 'DEVELOPMENT_INDEPENDENT_ACOUSTIC_EVALUATION',
        'realAudioValidation': 'NOT_RUN', 'productionApproved': False}
    (args.output / 'export.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt), flush=True)


if __name__ == '__main__':
    main()
