"""Opt-in genuine model/PCM session test. No test recognizer or expected prompt.

Spliced, hash-verified public reciter clips are diagnostic transition fixtures,
not an unseen natural learner session. ASGI WebSocket test transport here; real
TCP measurements are separately produced by evaluate.py.
"""
import hashlib
import json
import os
from pathlib import Path
import numpy as np
import pytest
from fastapi.testclient import TestClient
from noor_engine.api import create_app
from conftest import ROOT


@pytest.mark.skipif(not os.getenv('NOOR_REAL_MODEL_PATH'), reason='Actual pinned model/fixtures must be explicitly supplied; no mock acoustic pass')
def test_actual_model_continuous_windows_recover_and_change_surah(settings, signed_identity, tmp_path):
    from dataclasses import replace
    from faster_whisper.audio import decode_audio
    settings = replace(settings, model_path=Path(os.environ['NOOR_REAL_MODEL_PATH']))
    fixtures = Path(os.environ['NOOR_PUBLIC_FIXTURES'])
    sources = {s['file']:s for s in json.loads((ROOT/'tools/RecitationEngineProbe/fixtures/sources.json').read_text())}
    audio = []
    for name in ['112001.mp3', '112002.mp3', '114001.mp3']:
        path = fixtures/name
        assert hashlib.sha256(path.read_bytes()).hexdigest() == sources[name]['sha256']
        audio.append(decode_audio(str(path), sampling_rate=16000))
    samples = np.concatenate(audio).astype('<f4')
    app = create_app(settings, verifier=signed_identity[0])
    results, locations = [], []
    with TestClient(app) as client:
        assert client.get('/health/ready').status_code == 200
        # Only the local evaluation principal bypasses external Apple network
        # access. All acoustic inference and canonical binding are genuine.
        tokens = app.state.store.login('isolated-public-audio-evaluation')
        headers = {'Authorization':'Bearer '+tokens['access_token']}
        start = client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'})
        assert start.status_code == 201
        sid = start.json()['session_id']
        ends = list(range(min(128000,len(samples)), len(samples), 32000))+[len(samples)]
        for sequence, end in enumerate(ends):
            first = max(0, end-128000)
            with client.websocket_connect(f'/v1/sessions/{sid}/audio', headers=headers) as ws:
                ws.send_json({'sequence':sequence,'start_frame':first,'end_frame':end})
                ws.send_bytes(samples[first:end].tobytes())
                result = ws.receive_json()
                assert 'error' not in result, result
                results.append(result)
                locations.extend(e['payload']['verse'] for e in result['events'] if e['type']=='VERSE_LOCATION_CHANGED')
                assert all(e['type']!='ERROR_CONFIRMED' for e in result['events'])
        state = client.get('/v1/sessions/'+sid, headers=headers).json()
        report={'scope':__doc__, 'model':app.state.recognizer.model_id,'revision':app.state.recognizer.revision,
                'source_files':[sources[n] for n in ['112001.mp3','112002.mp3','114001.mp3']],
                'audio_frames':len(samples),'windows':len(results),'reported_transitions':locations,
                'final_state':state['state'], 'window_results':results}
        output = os.getenv('NOOR_AUDIO_EVIDENCE_OUTPUT')
        if output: Path(output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        assert any(v.startswith('112:') for v in locations)
        assert locations[-1] == '114:1'
        assert all(v.startswith(('112:','114:')) for v in locations)
        assert any(e['verse']=='114:1' for e in state['state']['evidence'])
        client.delete('/v1/sessions/'+sid,headers=headers)


@pytest.mark.skipif(not os.getenv('NOOR_REAL_MODEL_PATH'), reason='Real capacity probe requires the actual pinned CPU model')
def test_actual_cpu_admission_bounds_concurrent_sessions(settings, signed_identity):
    from dataclasses import replace
    from concurrent.futures import ThreadPoolExecutor
    import threading
    import time
    from faster_whisper.audio import decode_audio
    from starlette.websockets import WebSocketDisconnect
    settings = replace(settings, model_path=Path(os.environ['NOOR_REAL_MODEL_PATH']))
    path = Path(os.environ['NOOR_PUBLIC_FIXTURES'])/'112001.mp3'
    source = next(s for s in json.loads((ROOT/'tools/RecitationEngineProbe/fixtures/sources.json').read_text()) if s['file']==path.name)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == source['sha256']
    samples = decode_audio(str(path), sampling_rate=16000).astype('<f4')
    app = create_app(settings, verifier=signed_identity[0])
    with TestClient(app) as client:
        sessions = []
        for n in range(5):
            tokens = app.state.store.login('isolated-capacity-test-'+str(n))
            headers = {'Authorization':'Bearer '+tokens['access_token']}
            response = client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'})
            assert response.status_code == 201
            sessions.append((response.json()['session_id'],headers))
        barrier = threading.Barrier(5)
        release = threading.Event()
        def work(pair):
            sid, headers = pair
            with client.websocket_connect(f'/v1/sessions/{sid}/audio',headers=headers) as ws:
                barrier.wait(timeout=15)
                ws.send_json({'sequence':0,'start_frame':0,'end_frame':len(samples)})
                ws.send_bytes(samples.tobytes())
                started = time.monotonic(); result = ws.receive_json()
                release.wait(timeout=30)
                return {'elapsed_seconds':time.monotonic()-started, 'result':result}
        with ThreadPoolExecutor(max_workers=4) as executor:
            jobs = [executor.submit(work,pair) for pair in sessions[:4]]
            barrier.wait(timeout=15)
            rejected = False
            try:
                sid, headers = sessions[4]
                with client.websocket_connect(f'/v1/sessions/{sid}/audio',headers=headers): pass
            except WebSocketDisconnect: rejected = True
            # All connections remain open until the admission assertion runs.
            release.set()
            results = [j.result(timeout=40) for j in jobs]
        completed = [r for r in results if 'error' not in r['result']]
        busy = [r for r in results if r['result'].get('error')=='engine_busy']
        assert rejected and len(completed)==1 and len(busy)==3
        report={'scope':'Actual model plus four ASGI WebSocket sessions; fifth rejected. Not a sustained concurrency/SLA or internet test.',
                'cpu_threads':settings.cpu_threads,'actual_inferences':len(completed),'busy_responses':len(busy),
                'fifth_connection_rejected':rejected,'results':results}
        output = os.getenv('NOOR_CAPACITY_EVIDENCE_OUTPUT')
        if output: Path(output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        for sid, headers in sessions: client.delete('/v1/sessions/'+sid,headers=headers)
