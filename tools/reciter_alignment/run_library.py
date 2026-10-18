"""Resumable real-recording timing audit; no automatic production promotion.

Run all114surahs/all20records with a bounded local compute time. One downloaded
public recording at a time; audio is removed after source hash and results are
persisted. Mobile apps never download these development models.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import traceback

import verify_catalog
from quran_ctc import REVISION
from audit import complete_report, fingerprint, library_coverage, write_json


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--onnx',type=Path)
    parser.add_argument('--precision',choices=('float16','float32'),default='float16')
    parser.add_argument('--max-minutes',type=int,default=30)
    parser.add_argument('--surahs',default='all')
    args=parser.parse_args()
    if not 1<=args.max_minutes<=60:raise ValueError('Explicit bounded local compute1..60minutes')
    root=Path(__file__).resolve().parents[2]
    canonical_sha=hashlib.sha256((root/'content-sources/recitation-word-script.json').read_bytes()).hexdigest()
    catalog=json.loads((root/'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))['reciters']
    ids=[r['id'] for r in catalog]
    inputs=fingerprint(root)
    order=[1,112,113,114]+list(range(2,112)) if args.surahs=='all' else [int(x) for x in args.surahs.split(',')]
    if not order or len(set(order))!=len(order) or any(not 1<=s<=114 for s in order):raise ValueError('Invalid surah set')
    args.output.mkdir(parents=True,exist_ok=True)
    cache=args.output/'temporary-public-audio';cache.mkdir(exist_ok=True)
    deadline=time.monotonic()+60*args.max_minutes
    aligner=None
    if args.onnx:
        from quran_onnx import inference_identity
        runtime=inference_identity(args.precision,'whole')
    else:
        from quran_ctc import runtime_identity
        runtime=runtime_identity()
    progress={'scope':'PROFESSIONAL_RECITER_TIMING_ONLY','modelRevision':REVISION,
              'inputFingerprint':inputs,
              'inferenceRuntime':runtime,
              'canonicalScriptSHA256':canonical_sha,'requestedSurahs':order,'reciterIDs':ids,
              'productionWordTrackingComplete':False,'productionReview':'NOT_RUN',
              'records':{},'failures':{}}
    def save():
        write_json(args.output/'progress.json',progress)
    for surah in order:
        if time.monotonic()>=deadline:break
        report=args.output/f'{surah:03}'/'report.json'
        if report.exists():
            previous=json.loads(report.read_text(encoding='utf-8'))
            if complete_report(previous,inputs,surah,catalog,runtime):
                progress['records'][str(surah)]={'observed':20,'candidates':previous.get('measuredCandidates',0),'resumed':True}
                save();continue
        sys.argv=['verify_catalog.py','--quran-model','--ayah-windows','--stream-cache',
                  '--surah',str(surah),'--model',str(args.model),'--output',str(report.parent),'--audio-cache',str(cache)]
        if args.onnx:sys.argv+=['--onnx',str(args.onnx),'--precision',args.precision]
        try:
            aligner=verify_catalog.main(aligner,stop_at=deadline)
            observed=json.loads(report.read_text(encoding='utf-8'))
            progress['records'][str(surah)]={'observed':len(observed['records']),
                                             'candidates':observed.get('measuredCandidates',0)}
        except Exception as error:
            progress['failures'][str(surah)]={'type':type(error).__name__,'message':str(error)[:4000]}
            # Preserve the actual backend reason; a truncated arena message
            # cannot establish memory exhaustion or a model/recording defect.
            (args.output/f'{surah:03}-failure.txt').write_text(traceback.format_exc(),encoding='utf-8')
        save()
    progress['stopReason']='LOCAL_TIME_LIMIT' if time.monotonic()>=deadline else 'REQUESTED_PASS_FINISHED'
    progress['wholeRecordingCandidates']=sum(r['candidates'] for r in progress['records'].values())
    progress['expectedWholeRecordingsForFullLibrary']=114*len(ids)
    save()
    write_json(args.output/'full-library-coverage.json',library_coverage(root,[args.output]))
    print(json.dumps(progress,ensure_ascii=False),flush=True)


if __name__=='__main__':main()
