"""Independent public FastConformer source screening; never release approval.

Use only the publisher's pinned, ungated CC-BY4 archive. Restore numeric tensors
with weights_only=True into the known NeMo class. Never use restore_from(),
remote Python, a passage prompt, canonical replacement text or learner audio.
The original model is an offline baseline here, not a streaming implementation.
"""
from pathlib import Path
import faulthandler
import hashlib
import io
import json
import os
import subprocess
import tarfile
import time
import urllib.request

from probe_contract import (ARCHIVE, ARCHIVE_SHA, COMPLETE, CONFIG_SHA, END_MARKER,
                            EXPECTED_CASE_COUNT, MARKER, MODEL, REVISION, ROOT,
                            SCOPE, public_sources)

OUT = ROOT/'release/fastconformer-source-probe'
TARGETS = {
    'nemo.collections.asr.modules.'+name for name in
    ('AudioToMelSpectrogramPreprocessor','SpectrogramAugmentation',
     'ConformerEncoder','RNNTDecoder','RNNTJoint','ConvASRDecoder')
}


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1_048_576), b''):h.update(block)
    return h.hexdigest()


def check_targets(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == '_target_' and child not in TARGETS:
                raise ValueError('Unexpected executable configuration target')
            check_targets(child)
    elif isinstance(value, list):
        for child in value:check_targets(child)


def main():
    faulthandler.dump_traceback_later(420, exit=True)
    OUT.mkdir(parents=True, exist_ok=True)
    source_commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    report = {'schemaVersion':1,'sourceCommit':source_commit,
        'sourceModel':MODEL,'revision':REVISION,'archiveSHA256':ARCHIVE_SHA,
        'configurationSHA256':CONFIG_SHA,'scope':SCOPE,
        'appIntegrated':False,'productionApproved':False,'expectedPassageInput':False,
        'status':'STARTED','expectedCaseCount':EXPECTED_CASE_COUNT,
        'inferenceCaseCount':0,'inferenceCompleted':False,'cases':[]}
    def save():
        (OUT/'actual-source.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    save()
    (OUT/'source.txt').write_text(source_commit+'\n',encoding='utf-8')
    import numpy as np
    import torch
    import yaml
    from huggingface_hub import HfApi, hf_hub_download
    from omegaconf import OmegaConf
    torch.set_num_threads(4);torch.set_num_interop_threads(1)
    model_info = HfApi(token=False).model_info(MODEL,revision=REVISION,token=False)
    assert model_info.sha == REVISION and model_info.gated is False and model_info.card_data.license == 'cc-by-4.0'
    archive = Path(hf_hub_download(MODEL,ARCHIVE,revision=REVISION,token=False))
    assert archive.stat().st_size == 459243520 and digest(archive) == ARCHIVE_SHA
    folder = OUT/'source-tokenizer';folder.mkdir(exist_ok=True)
    with tarfile.open(archive, 'r:') as source:
        members = source.getmembers()
        config_item = next(x for x in members if x.name == './model_config.yaml')
        assert config_item.isfile() and config_item.size < 100000
        config_bytes = source.extractfile(config_item).read()
        assert hashlib.sha256(config_bytes).hexdigest() == CONFIG_SHA
        config = yaml.safe_load(config_bytes)
        check_targets(config)
        assert config['target'] == 'nemo.collections.asr.models.hybrid_rnnt_ctc_bpe_models.EncDecHybridRNNTCTCBPEModel'
        for key in ('model_path','vocab_path','spe_tokenizer_vocab'):
            original = config['tokenizer'][key]
            assert original.startswith('nemo:') and '/' not in original[5:]
            member = next(x for x in members if x.name == './'+original[5:])
            assert member.isfile() and member.size < 300000
            dest = folder/original[5:];dest.write_bytes(source.extractfile(member).read())
            config['tokenizer'][key] = str(dest.resolve())
        config['tokenizer']['dir'] = str(folder.resolve())
        for key in ('train_ds','validation_ds','test_ds'):config[key] = None
        weights = next(x for x in members if x.name == './model_weights.ckpt')
        assert weights.isfile() and weights.size < 460_000_000
        state = torch.load(io.BytesIO(source.extractfile(weights).read()), map_location='cpu', weights_only=True)
    from nemo.collections.asr.models import EncDecHybridRNNTCTCBPEModel
    started = time.monotonic()
    model = EncDecHybridRNNTCTCBPEModel(cfg=OmegaConf.create(config), trainer=None)
    model.load_state_dict(state,strict=True);del state
    model = model.cpu().float().eval()
    report.update(modelLoadSeconds=time.monotonic()-started,
        torchVersion=torch.__version__,sourceConfiguration='FP32/offline/full-context/CTC-head/no-RNNT-LM',
        featureConfiguration=config['preprocessor'])
    save()
    import av
    def pcm(path):
        resampler=av.AudioResampler(format='fltp',layout='mono',rate=16000)
        parts=[]
        with av.open(str(path)) as container:
            for frame in container.decode(audio=0):
                for converted in resampler.resample(frame):parts.append(converted.to_ndarray().reshape(-1))
            for converted in resampler.resample(None):parts.append(converted.to_ndarray().reshape(-1))
        value=np.concatenate(parts).astype(np.float32)
        assert 400 <= len(value) <= 256000 and np.isfinite(value).all()
        return value
    sources=public_sources()
    cases=[]
    for entry in sources:
        name=entry['file'];assert len(name)==10 and name[:6].isdigit() and name.endswith('.mp3')
        path=OUT/name
        if not path.is_file():
            with urllib.request.urlopen('https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/'+name,timeout=30) as r:
                data=r.read(2_000_001)
            assert len(data)<=2_000_000
            path.write_bytes(data)
        assert digest(path)==entry['sha256']
        original=pcm(path)
        for gain in (1.,.03):cases.append((name,'public-gain='+str(gain),original*np.float32(gain),entry['sha256']))
        if name in ('001002.mp3','002001.mp3'):cases.append((name,'public-first-two-seconds',original[:32000],entry['sha256']))
    cases.extend([('silence','generated-negative-control',np.zeros(16000,dtype=np.float32),None),
        ('noise','generated-negative-control',np.random.default_rng(14).normal(0,.001,16000).astype(np.float32),None)])
    assert len(cases)==EXPECTED_CASE_COUNT
    for name,kind,values,pin in cases:
        began=time.monotonic()
        with torch.inference_mode():
            features,length=model.preprocessor(input_signal=torch.from_numpy(values)[None,:],
                length=torch.tensor([len(values)],dtype=torch.long))
            encoded,encoded_length=model.encoder(audio_signal=features,length=length)
            logits=model.ctc_decoder(encoder_output=encoded)[0,:int(encoded_length[0])]
            assert logits.shape[1]==1025 and torch.isfinite(logits).all()
            labels=logits.argmax(-1).tolist()
        blank=1024
        ids=[label for i,label in enumerate(labels) if label != blank and (i==0 or label != labels[i-1])]
        raw=model.tokenizer.ids_to_text(ids)
        row={'file':name,'kind':kind,'sourceMP3SHA256':pin,'sourceFrames':len(values),
            'sourceFloatSHA256':hashlib.sha256(values.tobytes()).hexdigest(),'rawTranscript':raw,
            'rawTokenIDs':ids,'encoderFrames':len(labels),'seconds':time.monotonic()-began,
            'inferenceCompleted':True}
        report['cases'].append(row)
        report['inferenceCaseCount']=len(report['cases'])
        save();print(MARKER+json.dumps(row,ensure_ascii=False),flush=True)
    assert len(report['cases'])==EXPECTED_CASE_COUNT
    report.update(status=COMPLETE,inferenceCompleted=True);save()
    print(END_MARKER,flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        path=OUT/'actual-source.json'
        if path.is_file():
            report=json.loads(path.read_text(encoding='utf-8'))
            report.update(status='FAILED_INFERENCE_NOT_VERIFIED',inferenceCompleted=False,
                          errorType=type(error).__name__)
            path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        raise
