"""Evaluated separately: Quran-finetuned CTC, no remote code execution."""
import hashlib
import json
from pathlib import Path
import unicodedata
import numpy as np
from ctc import Aligner

REVISION='b539d5fa66deb820c8e4762171ecb284ace4b52d'
FILES={
    'model.safetensors':'202cb1eefd7c399d117140014dc773da358e895e6e6b2312d999e7fda503febf',
    'config.json':'56868371643cb1a350fa336b246882505c3aa87d86b31990808b426bb8175230',
    'vocab.json':'60b9e6174798b6e1a92c92fb5935e32522aebaca4cdd1f481fd220346471644c',
    'preprocessor_config.json':'ffc72f475cd79680d5d659fbaefc691cdbcee5c9703a15faf708a5e91452a8d8',
}


def runtime_identity():
    import torch
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    precision = 'float32' if device == 'cuda' else 'dynamic-int8'
    return f'pytorch{torch.__version__}/{device}/{precision}'


def verify_assets(model_dir):
    # Pins are code-reviewed, not accepted from an editable download receipt.
    model_dir=Path(model_dir)
    for name,expected in FILES.items():
        path=model_dir/name
        if path.is_symlink() or not path.is_file():raise ValueError('Pinned model asset missing/linked')
        digest=hashlib.sha256()
        with path.open('rb') as source:
            for chunk in iter(lambda:source.read(1024*1024),b''):digest.update(chunk)
        if digest.hexdigest()!=expected:raise ValueError('Quran alignment model digest differs')


class QuranAligner(Aligner):
    def __init__(self, model_dir, threads=4):
        import torch
        from transformers import Wav2Vec2ForCTC
        model_dir=Path(model_dir)
        verify_assets(model_dir)
        self.source_vocab=json.loads((model_dir/'vocab.json').read_text())
        letters=sorted({self.normalizer(c) for c in self.source_vocab
                        if len(c)==1 and self.normalizer(c) and c!='|'})
        self.vocab={'<pad>':0,'|':1,**{c:i+2 for i,c in enumerate(letters)}}
        self.device='cuda' if torch.cuda.is_available() else 'cpu'
        torch.set_num_threads(threads)
        # safetensors + explicit built-in class; never trust_remote_code.
        self.model=Wav2Vec2ForCTC.from_pretrained(str(model_dir),local_files_only=True,
                                              use_safetensors=True).eval().to(self.device)
        if self.device=='cpu':
            self.model=torch.ao.quantization.quantize_dynamic(self.model,{torch.nn.Linear},
                                                            dtype=torch.qint8,inplace=True)
        self.revision=REVISION
        self.runtime_identity=runtime_identity()

    def normalizer(self,text):
        text=unicodedata.normalize('NFC',text)
        text=text.translate(str.maketrans({'ٱ':'ا','أ':'ا','إ':'ا','آ':'ا'}))
        return ''.join(c for c in text if unicodedata.category(c).startswith('L')
                       and c not in 'ـۥۦ')

    def emissions(self,values):
        import torch
        with torch.inference_mode():
            values=torch.from_numpy(values).to(self.device)[None]
            logits=self.model(values).logits[0].float().cpu().numpy()
        peak=logits.max(axis=-1,keepdims=True)
        probabilities=np.exp(logits-peak)
        probabilities/=probabilities.sum(axis=-1,keepdims=True)
        projected=np.zeros((len(logits),len(self.vocab)),dtype=np.float32)
        for char,source_id in self.source_vocab.items():
            # Marginalize vowel/ornament labels into blank and spelling forms
            # into the same letter posterior. Do not force differently ordered
            # combining marks to consume a Quran word's acoustic frames.
            target=self.vocab['|'] if char=='|' else self.vocab.get(self.normalizer(char),0) if len(char)==1 else 0
            projected[:,target]+=probabilities[:,source_id]
        return np.log(np.maximum(projected,1e-30))
