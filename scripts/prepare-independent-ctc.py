"""Build-time only, exact tested CoreML source -> Apple's bundled compiled model.

The app never fetches or substitutes a model at runtime. Compilation is allowed
only after the source spec and weights match the actual26-case Mac experiment.
No test result is generated or rewritten here.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
PINS={
    'Data/com.apple.CoreML/model.mlmodel':'a03be761fad1c1da230d0c3522ae3be7e20523147603d219751ad2abaaced5d7',
    'Data/com.apple.CoreML/weights/weight.bin':'bb4a2ffd5eb4082d8383c721887294886594ba77ec0d4611b38ea1796e231833',
}
REVISION='b539d5fa66deb820c8e4762171ecb284ace4b52d'


def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):value.update(chunk)
    return value.hexdigest()


def verify_source(folder):
    files=set()
    for path in folder.rglob('*'):
        if path.is_symlink():raise ValueError('Linked independent CTC package')
        if path.is_file():files.add(path.relative_to(folder).as_posix())
    if files!=set(PINS)|{'Manifest.json'}:
        raise ValueError('Unexpected independent CTC package inventory')
    manifest=json.loads((folder/'Manifest.json').read_text())
    entries=manifest.get('itemInfoEntries',{})
    root=entries.get(manifest.get('rootModelIdentifier'),{})
    if (manifest.get('fileFormatVersion')!='1.0.0'
        or root.get('path')!='com.apple.CoreML/model.mlmodel'
        or len(entries)!=2 or {e.get('path') for e in entries.values()}
            !={'com.apple.CoreML/model.mlmodel','com.apple.CoreML/weights'}):
        raise ValueError('Independent CTC package root/weights mapping differs')
    for relative,pin in PINS.items():
        path=folder/relative
        if path.is_symlink() or not path.is_file():
            raise ValueError('Independent CTC source missing/linked: '+relative)
        actual=digest(path)
        if actual!=pin:
            raise ValueError('Independent CTC differs from actually tested source: '+relative+' actualSHA256='+actual+' expectedSHA256='+pin)


def inventory(folder):
    result={}
    for file in sorted(folder.rglob('*')):
        if file.is_symlink():raise ValueError('Linked compiled CTC asset')
        if file.is_file() and file.name!='verified-model.json':
            result[file.relative_to(folder).as_posix()]=digest(file)
    return result


def main():
    if sys.platform!='darwin':raise ValueError('CoreML compile requires Mac build host')
    compiler=subprocess.check_output(['xcodebuild','-version'],text=True).strip()
    destination=ROOT/'ios/IndependentCTC'
    descriptor_path=destination/'verified-model.json'
    if descriptor_path.is_file():
        current=json.loads(descriptor_path.read_text())
        if (current.get('revision')==REVISION and current.get('compiler')==compiler
            and current.get('convertedWeightsSHA256')==PINS['Data/com.apple.CoreML/weights/weight.bin']
            and current.get('sourceSpecSHA256')==PINS['Data/com.apple.CoreML/model.mlmodel']
            and current.get('files')==inventory(destination)):
            # A mutable compiled-cache receipt is not authority to replace a
            # reviewed graph. Compile again from byte-pinned source below.
            pass
        else:
            raise ValueError('Cached compiled CTC differs; preserve it for diagnosis instead of overwriting')
    cache=ROOT/'release/independent-coreml-model-seed0-float32'
    source=cache/'quran-ctc-float32.mlpackage'
    if not source.exists():
        from coreml_build_runtime import prepare as prepare_converter_runtime
        runtime=prepare_converter_runtime(ROOT, '/tmp/noor-coreml-py311-runtime')
        cache.parent.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='ctc-build-',dir=cache.parent) as temporary:
            work=Path(temporary)
            subprocess.run([str(runtime),str(ROOT/'tools/reciter_alignment/export_coreml.py'),
                '--model',str(Path.home()/'.cache/noor-independent-ctc'),
                '--output',str(work),'--precision','float32','--prepare-only'],
                env=dict(os.environ,PYTHONHASHSEED='0'),check=True)
            try:
                verify_source(work/'quran-ctc-float32.mlpackage')
            except ValueError:
                # Preserve the unexpected graph for diagnosis. A failed pin
                # never authorizes replacing the reviewed source/compiled model.
                failed=ROOT/'release/independent-coreml-source-mismatch'
                failed.mkdir(exist_ok=True)
                package=work/'quran-ctc-float32.mlpackage'
                actual={name:digest(package/name) if (package/name).is_file()
                    and not (package/name).is_symlink() else 'MISSING_OR_LINKED' for name in PINS}
                graph=package/'Data/com.apple.CoreML/model.mlmodel'
                if graph.is_file() and not graph.is_symlink():
                    shutil.copyfile(graph,failed/(actual['Data/com.apple.CoreML/model.mlmodel']+'.mlmodel'))
                (failed/'actual-source.json').write_text(json.dumps({'expected':PINS,'actual':actual,
                    'approved':False,'compiler':compiler},indent=2)+'\n',encoding='utf-8')
                raise
            cache.mkdir(exist_ok=True)
            shutil.copytree(work/'quran-ctc-float32.mlpackage',source)
    verify_source(source)
    if destination.exists() and not descriptor_path.is_file():
        raise ValueError('Refusing incomplete/existing compiled CTC destination')
    destination.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ctc-compiled-',dir=destination.parent) as temporary:
        work=Path(temporary)
        subprocess.run(['xcrun','coremlcompiler','compile',str(source),str(work)],check=True)
        compiled=work/'quran-ctc-float32.mlmodelc'
        if not compiled.is_dir():raise ValueError('Apple compiler did not produce the expected model')
        if destination.exists():
            if destination.is_symlink() or destination.resolve().parent != (ROOT/'ios').resolve():
                raise ValueError('Invalid generated model target')
            destination.rename(work/'previous-generated-model')
        destination.mkdir()
        shutil.copytree(compiled,destination/'quran-ctc.mlmodelc')
    vocabulary=ROOT/'content-sources/independent-ctc-vocab.json'
    if digest(vocabulary)!='60b9e6174798b6e1a92c92fb5935e32522aebaca4cdd1f481fd220346471644c':
        raise ValueError('Independent acoustic vocabulary changed')
    shutil.copyfile(vocabulary,destination/'vocab.json')
    shutil.copyfile(ROOT/'docs/QURAN-CTC-MODEL-NOTICE.txt',destination/'NOTICE.txt')
    descriptor={'schema':1,'revision':REVISION,'precision':'float32','compiler':compiler,
        'sourceWeightsSHA256':'202cb1eefd7c399d117140014dc773da358e895e6e6b2312d999e7fda503febf',
        'convertedWeightsSHA256':PINS['Data/com.apple.CoreML/weights/weight.bin'],
        'sourceSpecSHA256':PINS['Data/com.apple.CoreML/model.mlmodel'],
        'verificationScope':'26fixed public/prefix/negative conversion cases; NOT natural learner or hardware acceptance',
        'files':inventory(destination)}
    descriptor_path.write_text(json.dumps(descriptor,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    print('NOOR_INDEPENDENT_CTC_BUNDLED_ASSETS_VERIFIED')


if __name__=='__main__':main()
