"""Real-audio timing candidates for any canonical surah and catalog recording.

Measured coverage, failed words and production review are separate. Public
professional recordings only; never microphone or learner recordings.
"""
import argparse
import concurrent.futures
import gzip
import hashlib
import json
from pathlib import Path
import time
import urllib.request

import numpy as np
from faster_whisper.audio import decode_audio
from ctc import Aligner, validate_recording_spans


def main(existing_aligner=None, stop_at=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--quran-model',action='store_true')
    parser.add_argument('--audio-cache',type=Path)
    parser.add_argument('--reciter',type=int,action='append')
    parser.add_argument('--ayah-windows',action='store_true')
    parser.add_argument('--surah',type=int,default=1)
    parser.add_argument('--stream-cache',action='store_true',help='One public audio asset at a time, delete own temporary audio after its hash/receipt is stored')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    root=Path(__file__).resolve().parents[2]
    catalog=json.loads((root/'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))['reciters']
    if args.reciter:catalog=[r for r in catalog if r['id'] in args.reciter]
    if not catalog:raise ValueError('No selected catalog recordings')
    snap=json.loads(gzip.decompress((root/'content-sources/mushaf-snapshot.json.gz').read_bytes()))
    lexical=json.loads((root/'content-sources/recitation-word-script.json').read_text(encoding='utf-8'))
    if not 1<=args.surah<=114:raise ValueError('Invalid canonical surah')
    corpus=json.loads((root/'ios/Athar/quran.json').read_text(encoding='utf-8'))
    verse_offset=sum(len(s['ayahs']) for s in corpus[:args.surah-1])
    words=[];by_ayah={}
    for ayah in range(1,len(corpus[args.surah-1]['ayahs'])+1):
        records=sorted((r for r in snap['records'] if r['record_type']=='mushaf_word'
                        and r['char_type_name']=='word' and r['verse_id']==verse_offset+ayah),
                       key=lambda r:r['position_in_verse'])
        groups=lexical['groups'][f'{args.surah}:{ayah}']
        assert len(records)==len(groups)
        by_ayah[ayah]=[(r['id'],' '.join(g[3])) for r,g in zip(records,groups)]
        words.extend(by_ayah[ayah])
    published=json.loads((root/'ios/Athar/surah-ayah-timings.json').read_text(encoding='utf-8'))['recordings']
    def fetch(reciter):
        url=reciter['server']+f'{args.surah:03}.mp3'
        path=(args.audio_cache or args.output)/f"{reciter['id']}-{args.surah:03}.mp3"
        if path.is_symlink():raise ValueError('Audio cache may not be a symlink')
        if not path.exists():
            import shutil
            if shutil.disk_usage(args.output).free<1_000_000_000:raise ValueError('Keep1GB disk reserve; no audio fetched')
            with urllib.request.urlopen(url,timeout=45) as response:
                audio=response.read(128_000_001)
            if len(audio)>128_000_000:raise ValueError('Oversized public recording')
            path.write_bytes(audio)
        return reciter,path,url
    if args.stream_cache:jobs=(fetch(reciter) for reciter in catalog)
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            jobs=list(pool.map(fetch,catalog))
    if existing_aligner is not None:aligner=existing_aligner
    elif args.quran_model:
        from quran_ctc import QuranAligner
        aligner=QuranAligner(args.model)
    else:aligner=Aligner(args.model)
    report={'scope':'SELECTED_CATALOG_RECITERS_REAL_PUBLIC_AUDIO','surah':args.surah,
            'canonicalScriptSHA256':hashlib.sha256((root/'content-sources/recitation-word-script.json').read_bytes()).hexdigest(),
            'selectedReciterIDs':[r['id'] for r in catalog],
            'releaseStatus':'CANDIDATES_NOT_SHIPPED; full114/allwords/acoustic-review incomplete',
            'modelRevision':getattr(aligner,'revision',None),
            'ayahWindowPolicy':'Exact publisher recording boundaries with400ms acoustic context; no interpolation' if args.ayah_windows else None,
            'records':[],'controls':[]}
    control_pcm=None
    for reciter,path,url in jobs:
        if stop_at is not None and time.monotonic()>=stop_at:break
        pcm=decode_audio(str(path),sampling_rate=16000)
        if control_pcm is None and len(pcm)<=1_920_000:control_pcm=pcm.copy()
        record={'reciterID':reciter['id'],'recordingID':reciter['recordingID'],
                'audioURL':url,'audioSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),
                'durationSeconds':len(pcm)/16000,'expectedNativeWords':len(words)}
        start=time.monotonic()
        try:
            timing=published.get(reciter['server']) if args.ayah_windows else None
            if timing and timing['recordingID']==reciter['recordingID'] and timing['reciterID']==reciter['id'] and str(args.surah) in timing['surahs']:
                spans=[];quality=[];errors=[];diagnostics={}
                for ayah,begin,end in timing['surahs'][str(args.surah)]:
                    start_frame=max(0,round(begin*16)-6400)
                    end_frame=min(len(pcm),round(end*16)+6400)
                    try:
                        result=aligner.align(pcm[start_frame:end_frame],by_ayah[ayah])
                        spans.extend([[w,start_frame//16+a,start_frame//16+b] for w,a,b in result['spans']])
                        quality.append(result['minimumWordPosterior'])
                    except ValueError as error:errors.append({'ayah':ayah,'reason':str(error)})
                    diagnostics[str(ayah)]=getattr(aligner,'diagnostics',None)
                record['ayahDiagnostics']=diagnostics
                record['acceptedNativeWords']=len(spans)
                if errors:record['rejectedAyahs']=errors;raise ValueError('One or more exact ayah windows rejected')
                if any(a[2]>b[1] for a,b in zip(spans,spans[1:])):raise ValueError('Measured words overlap across ayah boundary')
                record.update(spans=spans,minimumWordPosterior=min(quality),status='MEASURED_CANDIDATE_REQUIRES_REVIEW')
            else:record.update(aligner.align(pcm,words))
            validate_recording_spans(record['spans'],[w[0] for w in words],len(pcm)/16)
        except ValueError as error:record.update(status='REJECTED',reason=str(error))
        record['diagnostics']=getattr(aligner,'diagnostics',None)
        record['alignmentSeconds']=round(time.monotonic()-start,3)
        report['records'].append(record)
        (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(reciter['id'],record['status'],record.get('reason',''),record['alignmentSeconds'],flush=True)
        if args.stream_cache:
            cache=(args.audio_cache or args.output).resolve()
            if path.resolve().parent!=cache or path.is_symlink():raise ValueError('Unsafe cache cleanup target')
            path.unlink()
    # Negative inputs are genuine absence/noise controls, never acceptance audio.
    controls=[('silence',np.zeros(16000,dtype=np.float32),words),
            ('noise',np.random.default_rng(42).normal(0,.02,16000).astype(np.float32),words),
            ('wrong-known-text',control_pcm,[(100001,'قل هو الله أحد'),(100002,'الله الصمد'),(100003,'لم يلد ولم يولد')] if args.surah==1 else [(100001,'الحمد لله رب العالمين'),(100002,'الرحمن الرحيم')])]
    for name,pcm,target in controls:
        if pcm is None:
            report['controls'].append({'name':name,'status':'NOT_RUN_NO_BOUNDED_CLIP'});continue
        try:aligner.align(pcm,target);report['controls'].append({'name':name,'rejected':False})
        except ValueError as error:report['controls'].append({'name':name,'rejected':True,'reason':str(error)})
    report['measuredCandidates']=sum(r['status'].startswith('MEASURED') for r in report['records'])
    (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'measuredCandidates':report['measuredCandidates'],'controls':report['controls']},ensure_ascii=False))
    return aligner


if __name__=='__main__':main()
