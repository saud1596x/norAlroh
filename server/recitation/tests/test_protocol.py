import json
import numpy as np
import pytest
from starlette.websockets import WebSocketDisconnect
from noor_engine.protocol import AudioHeader
from noor_engine.inference import Busy, InferenceDeadline


def start(client, auth):
    headers = {'Authorization':'Bearer '+auth['access_token']}
    result = client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'})
    assert result.status_code == 201
    return result.json()['session_id'], headers


def send(ws, sequence=0, first=0, last=16000, samples=None):
    ws.send_json({'sequence':sequence, 'start_frame':first, 'end_frame':last})
    ws.send_bytes(samples if samples is not None else np.zeros(last-first, dtype='<f4').tobytes())
    return ws.receive_json()


def test_reconnect_replays_identical_result_and_recovers_sequence(client, auth):
    sid, headers = start(client, auth)
    with client.websocket_connect(f'/v1/sessions/{sid}/audio', headers=headers) as ws:
        result = send(ws)
        assert result['events'][0]['type'] == 'AUDIO_ACCEPTED'
        assert not any(e['type'].startswith('ERROR_') for e in result['events'])
    with client.websocket_connect(f'/v1/sessions/{sid}/audio', headers=headers) as ws:
        assert send(ws) == result
        next_result = send(ws, sequence=1, first=0, last=32000)
        assert next_result['events'][0]['event_id'] > result['events'][-1]['event_id']
    state = client.get('/v1/sessions/'+sid, headers=headers).json()
    assert state['next_sequence'] == 2 and state['end_frame'] == 32000


@pytest.mark.parametrize('sequence,first,last,raw', [
    (1,0,16000,None), (0,10,16010,None),
    (0,0,16000,np.full(16000, float('nan'), dtype='<f4').tobytes()),
    (0,0,16000,np.full(16000, 2, dtype='<f4').tobytes()), (0,0,16000,b'bad'),
], ids=['skipped-sequence', 'initial-gap', 'nan-pcm', 'clipped-pcm', 'wrong-byte-count'])
def test_invalid_pcm_order_and_gaps_do_not_commit(client, auth, sequence, first, last, raw):
    sid, headers = start(client, auth)
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(f'/v1/sessions/{sid}/audio', headers=headers) as ws:
            send(ws, sequence, first, last, raw)
    assert client.get('/v1/sessions/'+sid, headers=headers).json()['next_sequence'] == 0


def test_changed_replay_is_rejected(client, auth):
    sid, headers = start(client, auth)
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(f'/v1/sessions/{sid}/audio', headers=headers) as ws:
            send(ws)
            send(ws, samples=np.ones(16000, dtype='<f4').tobytes())
    assert client.get('/v1/sessions/'+sid, headers=headers).json()['next_sequence'] == 1


def test_capacity_and_revocation_on_existing_socket(client, app, auth):
    sid, headers = start(client, auth)
    assert client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'}).status_code == 429
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(f'/v1/sessions/{sid}/audio', headers=headers) as ws:
            send(ws)
            client.post('/v1/auth/logout', headers=headers)
            send(ws, sequence=1, first=0, last=32000)


def test_busy_engine_preserves_same_sequence_for_retry(client, app, auth):
    original = app.state.recognizer.recognize
    async def busy(samples): raise Busy()
    app.state.recognizer.recognize = busy
    sid, headers = start(client, auth)
    with client.websocket_connect(f'/v1/sessions/{sid}/audio', headers=headers) as ws:
        assert send(ws)['error'] == 'engine_busy'
        app.state.recognizer.recognize = original
        assert send(ws)['sequence'] == 0


def test_text_number_and_nonfinite_boundary_headers_rejected():
    for body in [{'sequence':'0','start_frame':0,'end_frame':16000},
                 {'sequence':0,'start_frame':0,'end_frame':True},
                 {'sequence':0,'start_frame':0,'end_frame':128001}]:
        with pytest.raises(ValueError): AudioHeader.model_validate(body)
