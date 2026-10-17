"""Real loopback HTTP/WebSocket→pinned ASR→canonical alignment evaluation.

Only hash-verified public fixtures. No personal recording, remote inference,
mock model, synthetic success or production identity. The harness creates an
ephemeral local test principal directly in its isolated test database.
This ten-clip diagnostic is NOT an unseen learner-quality acceptance set.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import socket
import threading
import time
import statistics
import tempfile
import sys
import numpy as np
import httpx
import uvicorn
from websockets.sync.client import connect
from cryptography.fernet import Fernet
from faster_whisper.audio import decode_audio
from noor_engine.api import create_app
from noor_engine.config import Settings
from noor_engine.corpus import normalize


def distance(left, right):
    row = list(range(len(right)+1))
    for i, a in enumerate(left, 1):
        following = [i]
        for j, b in enumerate(right, 1): following.append(min(following[-1]+1, row[j]+1, row[j-1]+(a!=b)))
        row = following
    return row[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus-root', type=Path, required=True)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source_hashes = {str(p.relative_to(args.corpus_root)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (args.corpus_root/'server/recitation').rglob('*') if p.is_file() and p.suffix in {'.py','.json','.txt'}}
    with tempfile.TemporaryDirectory() as temp:
        settings = Settings(database_url='sqlite:///'+str(Path(temp)/'evaluation.db'), data_key=Fernet.generate_key().decode(),
            corpus_root=args.corpus_root, model_path=args.model, environment='local')
        app = create_app(settings)
        bound = socket.socket(); bound.bind(('127.0.0.1', 0)); port = bound.getsockname()[1]
        server = uvicorn.Server(uvicorn.Config(app, host='127.0.0.1', port=port, log_level='warning',
            access_log=False, ws_max_size=524288, ws_max_queue=1, timeout_keep_alive=5))
        thread = threading.Thread(target=lambda:server.run(sockets=[bound]), daemon=True); thread.start()
        start = time.monotonic()
        while not server.started:
            if not thread.is_alive() or time.monotonic()-start>30: raise RuntimeError('server did not start')
            time.sleep(.02)
        try:
            base = f'http://127.0.0.1:{port}'
            client = httpx.Client(base_url=base, timeout=40, trust_env=False)
            ready = client.get('/health/ready'); ready.raise_for_status()
            principal = app.state.store.login('local-evaluation-public-fixtures')
            headers = {'Authorization':'Bearer '+principal['access_token']}
            sources = json.loads((args.corpus_root/'tools/RecitationEngineProbe/fixtures/sources.json').read_text())
            script = json.loads((args.corpus_root/'content-sources/recitation-word-script.json').read_bytes())
            cases = [('silence', np.zeros(128000, dtype='<f4'), [], None)]
            cases.append(('seeded-noise', np.random.default_rng(14).normal(0,.001,128000).astype('<f4'), [], None))
            for fixture in sources:
                path = args.fixtures/fixture['file']
                if hashlib.sha256(path.read_bytes()).hexdigest() != fixture['sha256']: raise ValueError('fixture integrity mismatch')
                samples = decode_audio(str(path), sampling_rate=16000)
                if len(samples)>128000: raise ValueError('reference clip exceeds bounded window; do not truncate ground truth')
                reference = [normalize(w) for g in script['groups'][fixture['verse']] for token in g[2] for w in token.split()]
                for gain in [1.,.03]: cases.append((fixture['verse']+f'/gain={gain}', (samples*gain).astype('<f4'), reference, fixture['verse']))
            results = []
            for name, samples, reference, verse in cases:
                response = client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'})
                admission_wait = 0
                if response.status_code == 429:
                    # Exercise the actual deployed admission policy, never
                    # clear its bucket or disable it to obtain a green report.
                    admission_wait = min(60, max(1, int(response.headers.get('Retry-After', '60'))))
                    time.sleep(admission_wait)
                    response = client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'})
                response.raise_for_status(); sid=response.json()['session_id']
                payload=samples.astype('<f4').tobytes(); header={'sequence':0,'start_frame':0,'end_frame':len(samples)}
                before=time.monotonic()
                with connect(f'ws://127.0.0.1:{port}/v1/sessions/{sid}/audio', additional_headers=headers, proxy=None, max_size=1000000) as ws:
                    ws.send(json.dumps(header));ws.send(payload);result=json.loads(ws.recv())
                latency=time.monotonic()-before
                if 'error' in result: raise RuntimeError(result['error'])
                replay_start=time.monotonic()
                with connect(f'ws://127.0.0.1:{port}/v1/sessions/{sid}/audio', additional_headers=headers, proxy=None) as ws:
                    ws.send(json.dumps(header));ws.send(payload);replay=json.loads(ws.recv())
                if replay != result: raise ValueError('reconnection replay changed committed result')
                resume=client.get('/v1/sessions/'+sid,headers=headers);resume.raise_for_status()
                if resume.json()['next_sequence']!=1: raise ValueError('invalid recovery state')
                actual=[normalize(w['text']) for w in result['words']]
                locations=[e['payload']['verse'] for e in result['events'] if e['type']=='VERSE_LOCATION_CHANGED']
                chars_left=''.join(reference);chars_right=''.join(actual)
                results.append({'case':name,'audio_seconds':len(samples)/16000,'reference_words':len(reference),
                    'recognized_words':len(actual),'word_edits':distance(reference,actual),'reference_characters':len(chars_left),
                    'character_edits':distance(chars_left,chars_right),'correct_verse':locations==[verse] if verse else None,
                    'reported_locations':locations,'false_control_location':bool(locations) if not verse else None,
                    'network_and_inference_seconds':latency,'inference_ms':result['inference_ms'],
                    'admission_wait_seconds':admission_wait,
                    'resume_replay_seconds':time.monotonic()-replay_start,'replay_identical':True,
                    'matched_word_events':sum(e['type']=='WORD_CONFIRMED' for e in result['events'])})
                client.delete('/v1/sessions/'+sid,headers=headers).raise_for_status()
                print(name, 'words',len(actual),'edits',results[-1]['word_edits'],'locations',locations,flush=True)
            speech=[r for r in results if r['reference_words']]
            latencies=sorted(r['network_and_inference_seconds'] for r in speech)
            report={'scope':'Real local TCP/WebSocket and CPU model on ten previously used public reference clips plus acoustic controls, normal/3% gain. Not unseen learner assessment, iOS microphone, GPU capacity, internet jitter, calibrated errors or Tajweed.',
                'platform':platform.platform(),'python':sys.version,'ready':ready.json(), 'source_hashes':source_hashes,
                'capacity_configuration':{'instances':1,'cpu_threads':settings.cpu_threads,'concurrent_inferences':1,'max_session_slots':4},
                'summary':{'word_error_rate':sum(r['word_edits'] for r in speech)/sum(r['reference_words'] for r in speech),
                    'character_error_rate':sum(r['character_edits'] for r in speech)/sum(r['reference_characters'] for r in speech),
                    'verse_detection_rate':sum(r['correct_verse'] for r in speech)/len(speech),
                    'median_latency_seconds':statistics.median(latencies),'p95_latency_seconds':latencies[max(0,int(np.ceil(len(latencies)*.95))-1)],
                    'identical_recovery_count':sum(r['replay_identical'] for r in results),
                    'false_error_alert_rate':None,'tajweed_quality':None,'unseen_learner_accuracy':None},'cases':results}
            (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            client.delete('/v1/account', headers=headers).raise_for_status()
            client.close()
        finally:
            server.should_exit=True;thread.join(timeout=30);bound.close()
            if thread.is_alive(): raise RuntimeError('server did not terminate')


if __name__ == '__main__': main()
