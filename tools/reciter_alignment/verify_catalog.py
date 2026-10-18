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


class LocalDeadline(Exception):
    pass


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
        check_deadline(stop_at)
        url=reciter['server']+f'{args.surah:03}.mp3'
        path=(args.audio_cache or args.output)/f"{reciter['id']}-{args.surah:03}.mp3"
        if path.is_symlink():raise ValueError('Audio cache may not be a symlink')
        if not path.exists():
            import shutil
            if shutil.disk_usage(args.output).free<1_000_000_000:raise ValueError('Keep1GB disk reserve; no audio fetched')
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
                        if total>128_000_000:raise ValueError('Oversized public recording')
                        sink.write(chunk)
                temporary.replace(path)
            finally:
                if temporary.exists():temporary.unlink()
        return reciter,path,url
    inputs=fingerprint(root)
    previous_path=args.output/'report.json'
    previous=json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else {}
    can_resume=compatible(previous,inputs,args.surah,catalog)
    previous_records={r['reciterID']:r for r in previous.get('records',[])} if can_resume else {}
    check_deadline(stop_at)
    if existing_aligner is not None:aligner=existing_aligner
    elif args.quran_model:
        from quran_ctc import QuranAligner
        aligner=QuranAligner(args.model)
    else:aligner=Aligner(args.model)
    report={'scope':'SELECTED_CATALOG_RECITERS_REAL_PUBLIC_AUDIO','surah':args.surah,
            'auditSchema':SCHEMA,'inputFingerprint':inputs,
            'canonicalScriptSHA256':hashlib.sha256((root/'content-sources/recitation-word-script.json').read_bytes()).hexdigest(),
            'selectedReciterIDs':[r['id'] for r in catalog],
            'releaseStatus':'CANDIDATES_NOT_SHIPPED; full114/allwords/acoustic-review incomplete',
            'modelRevision':getattr(aligner,'revision',None),
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
        try:
            _,path,url=fetch(reciter)
            pcm=decode_audio(str(path),sampling_rate=16000)
        except LocalDeadline:break
        except Exception as error:
            records[reciter['id']]={'reciterID':reciter['id'],'recordingID':reciter['recordingID'],
                'audioURL':reciter['server']+f'{args.surah:03}.mp3',
                'status':'FETCH_OR_DECODE_FAILED','reason':type(error).__name__+': '+str(error)[:250]}
            save_records()
            continue
        if control_pcm is None:
            # A bounded excerpt of the actual recording also permits negative
            # controls for long surahs; never substitute generated acceptance.
            control_pcm=pcm[:1_920_000].copy()
        if old is not None and old.get('status') in ('MEASURED_CANDIDATE_REQUIRES_REVIEW','REJECTED'):
            if args.stream_cache:path.unlink()
            continue
        record={'reciterID':reciter['id'],'recordingID':reciter['recordingID'],
                'audioURL':url,'audioSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),
                'durationSeconds':len(pcm)/16000,'expectedNativeWords':len(words)}
        if old is not None and old.get('audioSHA256')==record['audioSHA256']:
            record['ayahResults']=old.get('ayahResults',{})
        record['status']='IN_PROGRESS'
        records[reciter['id']]=record
        start=time.monotonic()
        try:
            timing=published.get(reciter['server']) if args.ayah_windows else None
            if timing and timing['recordingID']==reciter['recordingID'] and timing['reciterID']==reciter['id'] and str(args.surah) in timing['surahs']:
                align_windows(aligner,pcm,timing['surahs'][str(args.surah)],by_ayah,record,save_records,stop_at)
            else:
                check_deadline(stop_at)
                record.update(aligner.align(pcm,words))
            validate_recording_spans(record['spans'],[w[0] for w in words],len(pcm)/16)
        except LocalDeadline as error:record.update(status='LOCAL_TIME_LIMIT',reason=str(error))
        except ValueError as error:record.update(status='REJECTED',reason=str(error))
        record['diagnostics']=getattr(aligner,'diagnostics',None)
        record['alignmentSeconds']=round(time.monotonic()-start,3)
        save_records()
        print(reciter['id'],record['status'],record.get('reason',''),record['alignmentSeconds'],flush=True)
        if args.stream_cache:
            cache=(args.audio_cache or args.output).resolve()
            if path.resolve().parent!=cache or path.is_symlink():raise ValueError('Unsafe cache cleanup target')
            path.unlink()
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
