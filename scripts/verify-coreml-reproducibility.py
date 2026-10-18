"""Freeze only a real-parity-passed source package reproducible in a new process."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda:stream.read(1024*1024),b''):value.update(part)
    return value.hexdigest()


def main():
    first=ROOT/'release/independent-coreml'
    receipt=json.loads((first/'actual-conversion.json').read_text())
    precision=receipt.get('precision')
    if (receipt.get('status')!='ACTUAL_PARITY_FINISHED' or precision not in {'float16','float32'}
        or len(receipt.get('cases',[]))!=26 or receipt.get('allRawWordsEqual') is not True
        or any(row['convertedRawWords'] or row['sourceRawWords'] for row in receipt['cases']
               if row['caseKind']=='generated-negative-control')):
        raise ValueError('Actual public parity must pass before freezing a source package')
    runtime='/tmp/noor-coreml-runtime/bin/python'
    environment=dict(os.environ,PYTHONHASHSEED='0')
    with tempfile.TemporaryDirectory(prefix='ctc-repro-',dir=ROOT/'release') as temporary:
        second=Path(temporary)
        subprocess.run([runtime,str(ROOT/'tools/reciter_alignment/export_coreml.py'),
            '--model',str(Path.home()/'.cache/noor-independent-ctc'),'--output',str(second),
            '--prepare-only','--precision',precision],env=environment,check=True)
        pins={}
        for name in ['Data/com.apple.CoreML/model.mlmodel','Data/com.apple.CoreML/weights/weight.bin']:
            left=digest(first/f'quran-ctc-{precision}.mlpackage'/name)
            right=digest(second/f'quran-ctc-{precision}.mlpackage'/name)
            pins[name]=left
            if left!=right:raise ValueError('Independent processes produced different actual source bytes: '+name+' first='+left+' second='+right)
    cache=ROOT/f'release/independent-coreml-model-seed0-{precision}'
    package=cache/f'quran-ctc-{precision}.mlpackage'
    if package.exists():
        if any(digest(package/name)!=value for name,value in pins.items()):
            raise ValueError('Preserve mismatching frozen cache for inspection')
    else:
        cache.mkdir(exist_ok=True)
        shutil.copytree(first/f'quran-ctc-{precision}.mlpackage',package)
    proof={'scope':'ACTUAL26CASE_PARITY_AND_TWO_PROCESS_SOURCE_REPRODUCIBILITY_NOT_LEARNER_ACCEPTANCE',
        'pythonHashSeed':'0','precision':precision,'sourcePins':pins,'productionApproved':False,
        'currentAppNativeAcceptance':'NOT_RUN','cases':26,'sameWords':26}
    (first/'reproducibility.json').write_text(json.dumps(proof,indent=2)+'\n')
    print('NOOR_COREML_SOURCE_REPRODUCIBILITY',json.dumps(proof),flush=True)


if __name__=='__main__':main()
