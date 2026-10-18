"""Real-audio timing candidates for any canonical surah and catalog recording.

Measured coverage, failed words and production review are separate. Public
professional recordings only; never microphone or learner recordings.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import time
import urllib.request

import numpy as np
from faster_whisper.audio import decode_audio
from ctc import Aligner, validate_recording_spans
from audit import SCHEMA, AYAH_POLICY, compatible, controls_passed, exact_record, fingerprint, write_json
from quran_onnx import InferenceIntervalLimit, InferenceWorkDeadline
from stream_audio import pcm_blocks, bounded_pcm, windowed_pcm, AudioIntervalResourceLimit


class LocalDeadline(Exception):
    pass

class LocalDiskReserve(Exception):
    pass


def file_sha256(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()


def check_deadline(stop_at):
    if stop_at is not None and time.monotonic() >= stop_at:
        raise LocalDeadline('Local compute limit; remaining audio is not verified')


def validate_ayah_windows(windows, by_ayah, duration_ms):
    if (not isinstance(windows, list) or len(windows) != len(by_ayah)
            or any(not isinstance(row, list) or len(row) != 3
                   or any(type(x) is not int for x in row)
                   or row[0] != index+1 or row[1] < 0 or row[2] <= row[1]
                   or row[2] > duration_ms+50 for index, row in enumerate(windows))
            or any(a[2] > b[1] for a, b in zip(windows, windows[1:]))):
        raise ValueError('Publisher ayah clock/coverage differs from exact recording')


def align_windows(aligner, pcm, windows, by_ayah, record, save, stop_at=None):
    """Checkpoint each actual ayah. Resume only after audio hash/policy match."""
    validate_ayah_windows(windows, by_ayah, len(pcm)/16)
    results = record.setdefault('ayahResults', {})
    for ayah, begin, end in windows:
        check_deadline(stop_at)
        cached = results.get(str(ayah))
        if cached is not None:
            if cached.get('status') == 'REJECTED':
                continue
            try:
                validate_recording_spans(cached['spans'], [w[0] for w in by_ayah[ayah]], len(pcm)/16)
                if not 0 <= cached['minimumWordPosterior'] <= 1:
                    raise ValueError('Invalid cached acoustic posterior')
                continue
            except (KeyError, TypeError, ValueError):
                results.pop(str(ayah), None)
        start_frame = max(0, round(begin*16)-6400)
        end_frame = min(len(pcm), round(end*16)+6400)
        try:
            aligned = aligner.align(pcm[start_frame:end_frame], by_ayah[ayah])
            spans = [[w, start_frame//16+a, start_frame//16+b] for w,a,b in aligned['spans']]
            validate_recording_spans(spans, [w[0] for w in by_ayah[ayah]], len(pcm)/16)
            results[str(ayah)] = {'status': 'MEASURED_CANDIDATE_REQUIRES_REVIEW',
                'spans': spans, 'minimumWordPosterior': aligned['minimumWordPosterior'],
                'diagnostics': getattr(aligner, 'diagnostics', None)}
        except ValueError as error:
            results[str(ayah)] = {'status': 'REJECTED', 'reason': str(error),
                                 'diagnostics': getattr(aligner, 'diagnostics', None)}
        save()
    failed = [{'ayah': ayah, 'reason': results[str(ayah)]['reason']}
              for ayah in by_ayah if results[str(ayah)]['status'] == 'REJECTED']
    record['acceptedNativeWords'] = sum(len(r.get('spans', [])) for r in results.values())
    if failed:
        record['rejectedAyahs'] = failed
        raise ValueError('One or more exact ayah windows rejected')
    spans = [span for ayah in by_ayah for span in results[str(ayah)]['spans']]
    validate_recording_spans(spans, [word[0] for words in by_ayah.values() for word in words], len(pcm)/16)
    record.update(spans=spans, minimumWordPosterior=min(r['minimumWordPosterior'] for r in results.values()),
                  status='MEASURED_CANDIDATE_REQUIRES_REVIEW')


def align_known_recording(aligner, pcm, windows, by_ayah, record, save, stop_at=None):
    """Try independent whole-recording CTC for short rejected publisher clocks.

    No clamping, adjusted text or relaxed acoustic threshold. Retain the failed
    publisher proposal for review. This is never applied to learner recordings.
    """
    try:
        align_windows(aligner, pcm, windows, by_ayah, record, save, stop_at)
        record['alignmentMethod'] = 'EXACT_PUBLISHER_AYAH_WINDOWS_CTC'
    except ValueError as error:
        if len(pcm) > 480_000:
            raise
        check_deadline(stop_at)
        record['publisherProposalFailure'] = str(error)
        words = [word for group in by_ayah.values() for word in group]
        result = aligner.align(pcm, words)
        validate_recording_spans(result['spans'], [word[0] for word in words], len(pcm)/16)
        record.update(result, alignmentMethod='WHOLE_SHORT_RECORDING_CTC_NO_PUBLISHER_CLOCK')


def align_streamed_recording(aligner,path,windows,by_ayah,record,save,stop_at=None):
    if not windows:raise ValueError('Missing exact publisher windows')
    validate_ayah_windows(windows,by_ayah,windows[-1][2])
    results=record.setdefault('ayahResults',{})
    def unavailable(ayah):
        results[str(ayah)]={'status':'RESOURCE_LIMIT_NOT_ASSESSED','reason':'Actual ayah exceeds bounded45second whole CTC interval'}
        save()
    def align(ayah,first,pcm):
        check_deadline(stop_at)
        cached=results.get(str(ayah))
        if cached and cached.get('status')=='REJECTED':return
        if cached and cached.get('status')=='MEASURED_CANDIDATE_REQUIRES_REVIEW':
            try:
                validate_recording_spans(cached['spans'],[w[0] for w in by_ayah[ayah]],(first+len(pcm))/16)
                if cached['spans'][0][1]<first/16:raise ValueError('Cached span precedes actual window')
                return
            except (ValueError,KeyError,TypeError):results.pop(str(ayah),None)
        try:
            measured=aligner.align(pcm,by_ayah[ayah])
            spans=[[word,first//16+start,first//16+end] for word,start,end in measured['spans']]
            validate_recording_spans(spans,[w[0] for w in by_ayah[ayah]],(first+len(pcm))/16)
            results[str(ayah)]={'status':'MEASURED_CANDIDATE_REQUIRES_REVIEW','spans':spans,
                'minimumWordPosterior':measured['minimumWordPosterior'],'sourceFirstFrame':first,'sourceFrameCount':len(pcm),
                'diagnostics':getattr(aligner,'diagnostics',None)}
        except InferenceIntervalLimit as error:
            results[str(ayah)]={'status':'RESOURCE_LIMIT_NOT_ASSESSED','reason':str(error)}
        except ValueError as error:
            results[str(ayah)]={'status':'REJECTED','reason':str(error),'diagnostics':getattr(aligner,'diagnostics',None)}
        save()
    total,control,largest=windowed_pcm(pcm_blocks(path),windows,align,unavailable,
        check=lambda:check_deadline(stop_at))
    record.update(durationSeconds=total/16000,sourceFrameCount=total,maximumRetainedPCMFrames=largest,
                  alignmentMethod='EXACT_PUBLISHER_WINDOWS_SEQUENTIAL_S16_CTC1')
    validate_ayah_windows(windows,by_ayah,total/16)
    record['acceptedNativeWords']=sum(len(row.get('spans',[])) for row in results.values())
    save()
    if any(row['status']=='RESOURCE_LIMIT_NOT_ASSESSED' for row in results.values()):
        record['controlClipAvailable']=True
        return control,'RESOURCE_LIMIT_NOT_ASSESSED'
    if any(row['status']=='REJECTED' for row in results.values()):return control,'REJECTED'
    spans=[span for ayah in by_ayah for span in results[str(ayah)]['spans']]
    validate_recording_spans(spans,[w[0] for words in by_ayah.values() for w in words],total/16)
    record.update(spans=spans,minimumWordPosterior=min(row['minimumWordPosterior'] for row in results.values()))
    return control,'MEASURED_CANDIDATE_REQUIRES_REVIEW'


def main(existing_aligner=None, stop_at=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--quran-model',action='store_true')
    parser.add_argument('--onnx',type=Path,help='Pinned experimental CUDA export; never silently falls back to CPU')
    parser.add_argument('--precision',choices=('float16','float32'),default='float16')
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
        check_deadline(stop_at)
        url=reciter['server']+f'{args.surah:03}.mp3'
        path=(args.audio_cache or args.output)/f"{reciter['id']}-{args.surah:03}.mp3"
        if path.is_symlink():raise ValueError('Audio cache may not be a symlink')
        if not path.exists():
            import shutil
            if shutil.disk_usage(args.output).free<1_000_000_000:raise LocalDiskReserve('Keep1GB disk reserve; stop audit, do not mark recordings failed')
            remaining=45 if stop_at is None else max(.1,min(45,stop_at-time.monotonic()))
            # Never leave a partial download looking like a valid cached MP3.
            temporary=path.with_suffix('.mp3.partial')
            try:
                with urllib.request.urlopen(url,timeout=remaining) as response, temporary.open('wb') as sink:
                    total=0
                    while True:
                        check_deadline(stop_at)
                        chunk=response.read(256*1024)
                        if not chunk:break
                        total+=len(chunk)
                        if total>512_000_000:raise AudioIntervalResourceLimit('Public recording exceeds512MB development fetch limit')
                        if shutil.disk_usage(args.output).free<1_000_000_000:raise LocalDiskReserve('Keep1GB disk reserve during bounded fetch')
                        sink.write(chunk)
                temporary.replace(path)
            finally:
                if temporary.exists():temporary.unlink()
        return reciter,path,url
    inputs=fingerprint(root)
    previous_path=args.output/'report.json'
    previous=json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else {}
    check_deadline(stop_at)
    if existing_aligner is not None:aligner=existing_aligner
    elif args.onnx:
        if not args.quran_model:raise ValueError('ONNX requires pinned Quran model')
        from quran_onnx import QuranONNXAligner
        aligner=QuranONNXAligner(args.model,args.onnx,precision=args.precision)
    elif args.quran_model:
        from quran_ctc import QuranAligner
        aligner=QuranAligner(args.model)
    else:aligner=Aligner(args.model)
    if args.onnx:aligner.deadline=stop_at
    runtime=getattr(aligner,'runtime_identity',None)
    can_resume=compatible(previous,inputs,args.surah,catalog,runtime)
    previous_records={r['reciterID']:r for r in previous.get('records',[])} if can_resume else {}
    report={'scope':'SELECTED_CATALOG_RECITERS_REAL_PUBLIC_AUDIO','surah':args.surah,
            'auditSchema':SCHEMA,'inputFingerprint':inputs,
            'canonicalScriptSHA256':hashlib.sha256((root/'content-sources/recitation-word-script.json').read_bytes()).hexdigest(),
            'selectedReciterIDs':[r['id'] for r in catalog],
            'releaseStatus':'CANDIDATES_NOT_SHIPPED; full114/allwords/acoustic-review incomplete',
            'modelRevision':getattr(aligner,'revision',None),
            'inferenceRuntime':runtime,
            'ayahWindowPolicy':AYAH_POLICY if args.ayah_windows else None,
            'records':[],'controls':[]}
    if can_resume and controls_passed(previous):report['controls']=previous['controls']
    def save():
        report['measuredCandidates']=sum(r.get('status')=='MEASURED_CANDIDATE_REQUIRES_REVIEW' for r in report['records'])
        write_json(previous_path,report)
    # Keep unprocessed checkpoints as well as the current recording if a pass
    # ends mid-surah. Catalog order remains stable in every persisted receipt.
    records={}
    for reciter in catalog:
        old=previous_records.get(reciter['id'])
        if old is not None and exact_record(old,reciter,args.surah):records[reciter['id']]=old
    def save_records():
        report['records']=[records[r['id']] for r in catalog if r['id'] in records]
        save()
    control_pcm=None
    for reciter in catalog:
        if stop_at is not None and time.monotonic()>=stop_at:break
        old=records.get(reciter['id'])
        if old is not None and old.get('status') in ('MEASURED_CANDIDATE_REQUIRES_REVIEW','REJECTED'):
            if controls_passed(report) or control_pcm is not None:continue
            # Recover a real bounded control clip after a partial controls run.
        path=None
        timing=published.get(reciter['server']) if args.ayah_windows else None
        proposal=(timing['surahs'].get(str(args.surah)) if timing
            and timing['recordingID']==reciter['recordingID'] and timing['reciterID']==reciter['id'] else None)
        streamed=bool(proposal and proposal[-1][2]>30000 and args.onnx)
        try:
            _,path,url=fetch(reciter)
            pcm=None if streamed else bounded_pcm(path)
        except LocalDeadline:break
        except LocalDiskReserve:raise
        except AudioIntervalResourceLimit as error:
            records[reciter['id']]={'reciterID':reciter['id'],'recordingID':reciter['recordingID'],
                'audioURL':reciter['server']+f'{args.surah:03}.mp3','status':'RESOURCE_LIMIT_NOT_ASSESSED','reason':str(error)}
            if path is not None and args.stream_cache and path.exists():path.unlink()
            save_records();continue
        except Exception as error:
            records[reciter['id']]={'reciterID':reciter['id'],'recordingID':reciter['recordingID'],
                'audioURL':reciter['server']+f'{args.surah:03}.mp3',
                'status':'FETCH_OR_DECODE_FAILED','reason':type(error).__name__+': '+str(error)[:250]}
            save_records()
            continue
        if control_pcm is None and pcm is not None:
            # A bounded excerpt of the actual recording also permits negative
            # controls for long surahs; never substitute generated acceptance.
            control_pcm=pcm[:480_000 if args.onnx else 1_920_000].copy()
        if old is not None and old.get('status') in ('MEASURED_CANDIDATE_REQUIRES_REVIEW','REJECTED'):
            if args.stream_cache:path.unlink()
            continue
        record={'reciterID':reciter['id'],'recordingID':reciter['recordingID'],
                'audioURL':url,'audioSHA256':file_sha256(path),
                'expectedNativeWords':len(words)}
        if pcm is not None:record['durationSeconds']=len(pcm)/16000
        if old is not None and old.get('audioSHA256')==record['audioSHA256']:
            record['ayahResults']=old.get('ayahResults',{})
        record['status']='IN_PROGRESS'
        records[reciter['id']]=record
        start=time.monotonic()
        try:
            if streamed:
                bounded_control,status=align_streamed_recording(aligner,path,proposal,by_ayah,record,save_records,stop_at)
                if control_pcm is None:control_pcm=bounded_control
                record['status']=status
            elif timing and timing['recordingID']==reciter['recordingID'] and timing['reciterID']==reciter['id'] and str(args.surah) in timing['surahs']:
                align_known_recording(aligner,pcm,timing['surahs'][str(args.surah)],by_ayah,record,save_records,stop_at)
            else:
                check_deadline(stop_at)
                if len(pcm)>1_920_000:
                    raise InferenceIntervalLimit('Long whole recording needs separately evidenced ayah intervals')
                record.update(aligner.align(pcm,words))
            if not streamed:
                validate_recording_spans(record['spans'],[w[0] for w in words],len(pcm)/16)
        except LocalDeadline as error:record.update(status='LOCAL_TIME_LIMIT',reason=str(error))
        except InferenceWorkDeadline as error:record.update(status='LOCAL_TIME_LIMIT',reason=str(error))
        except InferenceIntervalLimit as error:record.update(status='RESOURCE_LIMIT_NOT_ASSESSED',reason=str(error))
        except ValueError as error:record.update(status='REJECTED',reason=str(error))
        record['diagnostics']=getattr(aligner,'diagnostics',None)
        record['alignmentSeconds']=round(time.monotonic()-start,3)
        save_records()
        print(reciter['id'],record['status'],record.get('reason',''),record['alignmentSeconds'],flush=True)
        if args.stream_cache:
            cache=(args.audio_cache or args.output).resolve()
            if path.resolve().parent!=cache or path.is_symlink():raise ValueError('Unsafe cache cleanup target')
            path.unlink()
        pcm=None
    # Negative inputs are genuine absence/noise controls, never acceptance audio.
    controls=[('silence',np.zeros(16000,dtype=np.float32),words),
            ('noise',np.random.default_rng(42).normal(0,.02,16000).astype(np.float32),words),
            ('wrong-known-text',control_pcm,[(100001,'قل هو الله أحد'),(100002,'الله الصمد'),(100003,'لم يلد ولم يولد')] if args.surah==1 else [(100001,'الحمد لله رب العالمين'),(100002,'الرحمن الرحيم')])]
    completed_controls={c['name']:c for c in report['controls'] if c.get('rejected') is True}
    for name,pcm,target in controls:
        if name in completed_controls:continue
        if stop_at is not None and time.monotonic()>=stop_at:
            completed_controls[name]={'name':name,'status':'NOT_RUN_LOCAL_TIME_LIMIT'};continue
        if pcm is None:
            completed_controls[name]={'name':name,'status':'NOT_RUN_NO_BOUNDED_CLIP'};continue
        try:aligner.align(pcm,target);completed_controls[name]={'name':name,'rejected':False}
        except ValueError as error:completed_controls[name]={'name':name,'rejected':True,'reason':str(error)}
    report['controls']=[completed_controls[name] for name,_,_ in controls]
    save_records()
    print(json.dumps({'measuredCandidates':report['measuredCandidates'],'controls':report['controls']},ensure_ascii=False))
    return aligner


if __name__=='__main__':main()
