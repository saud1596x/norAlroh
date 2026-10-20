"""Check the actual CPU speech runtime before downloading any model weights.

Success here proves imports and tiny synthetic array interoperability only.
It is never an ASR, streaming, accuracy, iPhone or publication acceptance result.
"""
import argparse
import importlib
from importlib import metadata
import json
from pathlib import Path
import platform
import re
import sys
import traceback

PINS = Path(__file__).with_name('requirements-runtime-linux.txt')


def read_pins(path=PINS):
    result = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r'([A-Za-z0-9_.-]+)(?:\[[A-Za-z0-9_,.-]+\])?==([A-Za-z0-9_.+-]+)', line)
        if not match:
            raise ValueError('Runtime requirements must use exact version pins')
        name, version = match.groups()
        if name in result:
            raise ValueError('Duplicate runtime package pin: ' + name)
        result[name] = version
    if not result:
        raise ValueError('Missing runtime package pins')
    return result


def verify_versions(pins, versions):
    for name, expected in pins.items():
        actual = versions.get(name)
        # CPU PyTorch uses the official +cpu local suffix; no other package
        # may silently inherit a locally modified version.
        accepted = actual == expected or (name in {'torch', 'torchaudio', 'torchvision'}
                                          and actual == expected + '+cpu')
        if not accepted:
            raise RuntimeError(f'Runtime version mismatch for {name}: expected {expected}, found {actual}')


def run_checks(report):
    import numpy as np
    import pyarrow as pa
    import pandas as pd
    import datasets
    import torch

    if sys.platform != 'linux' or sys.version_info[:2] != (3, 11):
        raise RuntimeError('The source probe runtime is Linux CPython 3.11 only')
    if torch.version.cuda is not None:
        raise RuntimeError('The source probe must keep the official CPU PyTorch build')
    # Imports can succeed while an extension fails when crossing the NumPy ABI.
    # This tiny generated numeric fixture is not audio or model evidence.
    values = np.asarray([0.125, -0.5, 1.0], dtype=np.float32)
    arrow = pa.array(values, type=pa.float32())
    np.testing.assert_array_equal(arrow.to_numpy(zero_copy_only=True), values)
    np.testing.assert_array_equal(pd.DataFrame({'sample': values})['sample'].to_numpy(), values)
    dataset = datasets.Dataset.from_dict({'sample': values.tolist()})
    np.testing.assert_array_equal(np.asarray(dataset['sample'], dtype=np.float32), values)
    report['arrayInteropVerified'] = True

    modules = ['av', 'yaml', 'transformers', 'peft', 'lightning',
               'pytorch_lightning', 'torchmetrics', 'scipy', 'sklearn', 'librosa']
    for name in modules:
        report['lastImport'] = name
        importlib.import_module(name)
        report['completedImports'].append(name)
    report['lastImport'] = 'nemo.collections.asr.models'
    models = importlib.import_module('nemo.collections.asr.models')
    model = getattr(models, 'EncDecHybridRNNTCTCBPEModel')
    expected = 'nemo.collections.asr.models.hybrid_rnnt_ctc_bpe_models'
    if model.__module__ != expected or model.__name__ != 'EncDecHybridRNNTCTCBPEModel':
        raise RuntimeError('Unexpected NeMo speech model class')
    report['modelClass'] = model.__module__ + '.' + model.__name__
    report['completedImports'].append('nemo.collections.asr.models')
    report['cpuOnly'] = True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    report = {'schemaVersion': 1, 'scope': 'Runtime imports and synthetic array ABI check only',
              'runtimeImportsVerified': False, 'arrayInteropVerified': False,
              'inferenceExecuted': False, 'productionApproved': False,
              'pythonVersion': platform.python_version(), 'platform': sys.platform,
              'versions': {}, 'completedImports': [], 'lastImport': None}
    code = 1
    try:
        pins = read_pins()
        for name in pins:
            try:
                report['versions'][name] = metadata.version(name)
            except metadata.PackageNotFoundError:
                report['versions'][name] = None
        verify_versions(pins, report['versions'])
        run_checks(report)
        report['runtimeImportsVerified'] = True
        code = 0
    except Exception as error:
        report['error'] = {'type': type(error).__name__, 'message': str(error)}
        traceback.print_exc()
    finally:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('SOURCE_PROBE_RUNTIME_IMPORTS_OK' if code == 0 else 'SOURCE_PROBE_RUNTIME_IMPORTS_FAILED')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
