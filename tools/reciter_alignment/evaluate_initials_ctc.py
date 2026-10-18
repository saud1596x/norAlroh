"""Independent raw CTC on public initials, not professional forced alignment.

The actual prefix/full audio are decoded without any reference text. Known
professional material cannot establish natural learner correction precision.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from faster_whisper.audio import decode_audio
from quran_ctc import QuranAligner
from quran_onnx import collapse_words


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model',type=Path,required=True)
    parser.add_argument('--fixtures',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--max-minutes',type=int,default=3)
    args=parser.parse_args()
    if not 1<=args.max_minutes<=5:raise ValueError('Explicit local1..5minute limit')
    manifest=json.loads((args.fixtures/'sources.json').read_text(encoding='utf-8'))
    chosen=[r for r in manifest['records'] if r['verse'] in {'2:1','19:1','20:1','36:1'}]
    if len(chosen)!=4 or any('sha256' not in r for r in chosen):raise ValueError('Missing exact public source')
    model=QuranAligner(args.model)
    report={'scope':'INDEPENDENT_RAW_CTC_INITIALS_PREFIX_DIAGNOSTIC_NOT_LEARNER_ACCEPTANCE',
        'modelRevision':model.revision,'inferenceRuntime':model.runtime_identity,
        'forcedAlignmentUsed':False,'productionApproved':False,'cases':[]}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    deadline=time.monotonic()+args.max_minutes*60
    def save():args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for source in chosen:
        surah,ayah=(int(x) for x in source['verse'].split(':'))
        if source['file']!=f'{surah:03}{ayah:03}.mp3':raise ValueError('Unexpected public fixture path')
        path=args.fixtures/source['file']
        if path.is_symlink() or path.stat().st_size>2_000_000 or hashlib.sha256(path.read_bytes()).hexdigest()!=source['sha256']:
            raise ValueError('Public bytes differ')
        pcm=decode_audio(str(path),sampling_rate=16000)
        for length in sorted({min(32000,len(pcm)),len(pcm)}):
            if time.monotonic()>=deadline:report['stopReason']='LOCAL_TIME_LIMIT';save();return
            if length>480000:raise ValueError('No unbounded or truncated acceptance')
            original=pcm[:length]
            values=(original-original.mean())/np.sqrt(original.var()+1e-7)
            started=time.monotonic();logp=model.emissions(values);elapsed=time.monotonic()-started
            words=collapse_words(logp,model.vocab,length)
            report['cases'].append({'source':source,'originalFrames':len(pcm),'decodedFrames':length,
                'prefixOnly':length<len(pcm),'inferenceSeconds':elapsed,'rawIndependentWords':words})
            save();print(source['verse'],length,[w['text'] for w in words],flush=True)
    report['stopReason']='REQUESTED_PASS_FINISHED';save()


if __name__=='__main__':main()
