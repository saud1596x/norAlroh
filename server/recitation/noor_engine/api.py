import asyncio
from contextlib import asynccontextmanager, suppress
import json
import logging
import time
from typing import Literal
from uuid import uuid4
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect, HTTPException, Depends
from fastapi.security import HTTPBearer
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from .config import Settings
from .corpus import Corpus
from .identity import IdentityVerifier, IdentityUnavailable
from .inference import Recognizer, Busy, InferenceDeadline
from .protocol import AudioHeader, SessionIntelligence
from .storage import Store
from .contracts import CredentialReply, ChallengeReply, ReadyReply, CreatedReply, RecoveryReply, WindowReply, ErrorReply

log = logging.getLogger('noor.requests')


class Body(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)


class AppleLogin(Body):
    identity_token: str = Field(min_length=1, max_length=16384)
    challenge: str = Field(min_length=1, max_length=64)


class FirebaseLogin(Body):
    identity_token: str = Field(min_length=1, max_length=16384)


class Refresh(Body):
    refresh_token: str = Field(min_length=20, max_length=256)


class Start(Body):
    consent: Literal['transient-audio-encrypted-recovery-1h']
    sample_rate: Literal[16000] = 16000
    format: Literal['f32le'] = 'f32le'


def create_app(settings, recognizer=None, verifier=None):
    store = Store(settings)
    corpus = Corpus(settings.corpus_root)
    recognizer = recognizer or Recognizer(settings.model_path, settings.inference_timeout, settings.cpu_threads, settings.device)
    verifier = verifier or IdentityVerifier(settings)
    intelligence = SessionIntelligence(corpus, recognizer.model_id, recognizer.revision)
    leases = set()
    counters = {'http_requests':0, 'audio_windows':0, 'replayed_windows':0, 'rejected_windows':0,
                'engine_busy':0, 'window_timeouts':0}

    async def purge_loop():
        while True:
            await asyncio.sleep(60)
            try:
                store.cleanup(); app.state.retention_healthy = True
            except Exception:
                app.state.retention_healthy = False
                log.error('retention_cleanup_unavailable')

    @asynccontextmanager
    async def lifespan(app):
        store.migrate(); store.cleanup()
        app.state.retention_healthy = True
        app.state.model_ready = False
        try:
            await asyncio.to_thread(recognizer.load)
            app.state.model_ready = True
        except Exception:
            # Deliberately no paths, stack, payload, identity or transcript log.
            log.error('model_unavailable')
        cleanup = asyncio.create_task(purge_loop())
        yield
        cleanup.cancel()
        with suppress(asyncio.CancelledError): await cleanup
        # Wait for actual non-cancellable compute before closing the process.
        if recognizer.pending is not None:
            with suppress(Exception): await asyncio.shield(recognizer.pending)
        store.engine.dispose()

    app = FastAPI(title='Noor Recitation API', version='1.0.0', lifespan=lifespan,
                  docs_url=None, redoc_url=None,
                  responses={status:{'model':ErrorReply} for status in [400,401,403,404,408,413,422,429,503]})
    app.state.store, app.state.recognizer, app.state.verifier = store, recognizer, verifier
    app.state.corpus = corpus
    bearer = HTTPBearer(auto_error=False)

    def owner_for(header):
        if not header or not header.startswith('Bearer ') or len(header) > 300:
            raise HTTPException(401, 'unauthorized')
        owner = store.authenticate(header[7:])
        if not owner: raise HTTPException(401, 'unauthorized')
        return owner

    def limited(key, maximum=30):
        if not store.limit(key, maximum): raise HTTPException(429, 'retry_later', headers={'Retry-After':'60'})

    @app.middleware('http')
    async def boundaries(request, call_next):
        request_id = uuid4().hex
        start = time.monotonic(); counters['http_requests'] += 1
        # Never trust X-Forwarded-For from arbitrary clients; trusted proxy is
        # configured at deployment. IP is HMAC-pseudonymized before storage.
        key = request.client.host if request.client else 'unknown'
        try:
            if request.url.path not in {'/health/live', '/health/ready'}:
                limited('http:' + key, 120)
            length = request.headers.get('content-length')
            if length is not None and (not length.isdecimal() or int(length) > 24576):
                raise HTTPException(413, 'request_too_large')
            if request.method in {'POST', 'PUT', 'PATCH'}:
                # Bound chunked JSON too, without first buffering unbounded data.
                body = bytearray()
                async with asyncio.timeout(10):
                    async for part in request.stream():
                        body.extend(part)
                        if len(body) > 24576: raise HTTPException(413, 'request_too_large')
                async def replay(): return {'type':'http.request', 'body':bytes(body), 'more_body':False}
                request._receive = replay
                request._body = bytes(body)
            response = await call_next(request)
        except HTTPException as error:
            response = JSONResponse({'detail':error.detail}, status_code=error.status_code, headers=error.headers)
        except asyncio.TimeoutError:
            response = JSONResponse({'detail':'request_timeout'}, status_code=408)
        response.headers.update({'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff',
                                 'Referrer-Policy':'no-referrer', 'X-Request-ID':request_id})
        # No URL query, Authorization, owner, corpus position or text is logged.
        log.info(json.dumps({'request_id':request_id, 'status':response.status_code,
                             'elapsed_ms':round((time.monotonic()-start)*1000, 2)}))
        return response

    @app.exception_handler(ValidationError)
    async def validation_error(request, error): return JSONResponse({'detail':'invalid_request'}, status_code=422)

    # FastAPI's default validation response echoes bad input (potential identity
    # tokens). Replace it with a non-reflecting error at this public boundary.
    from fastapi.exceptions import RequestValidationError
    @app.exception_handler(RequestValidationError)
    async def request_error(request, error): return JSONResponse({'detail':'invalid_request'}, status_code=422)

    @app.get('/health/live')
    def live(): return {'service':'noor-recitation', 'version':1}

    @app.get('/health/ready', response_model=ReadyReply)
    def ready():
        if not app.state.model_ready: raise HTTPException(503, 'model_unavailable')
        if not getattr(recognizer, 'healthy', True): raise HTTPException(503, 'engine_stalled')
        if not app.state.retention_healthy: raise HTTPException(503, 'retention_unavailable')
        try:
            with store.engine.connect() as c:
                from sqlalchemy import text
                c.execute(text('SELECT 1'))
        except Exception: raise HTTPException(503, 'database_unavailable') from None
        return {'ready':True, 'model_id':recognizer.model_id, 'model_revision':recognizer.revision,
                'corpus_version':corpus.version, 'wording_assessment':'uncalibrated', 'tajweed_assessment':'unsupported',
                'word_evidence_version':2}

    @app.post('/v1/auth/apple/challenge', response_model=ChallengeReply)
    def challenge(request: Request):
        limited('challenge:' + (request.client.host if request.client else 'unknown'), 10)
        return store.challenge()

    @app.post('/v1/auth/apple', response_model=CredentialReply)
    async def apple(body: AppleLogin, request: Request):
        limited('login:' + (request.client.host if request.client else 'unknown'), 10)
        try:
            claims = await verifier.verify(body.identity_token, 'apple')
            if not isinstance(claims.get('nonce'), str) or not store.consume_challenge(body.challenge, claims['nonce']):
                raise ValueError('nonce replay or mismatch')
        except IdentityUnavailable: raise HTTPException(503, 'identity_provider_unavailable') from None
        except Exception: raise HTTPException(401, 'invalid_identity') from None
        result = store.login('apple:' + claims['sub'], claims['iat'])
        if not result: raise HTTPException(401, 'fresh_identity_required')
        return result

    @app.post('/v1/auth/firebase', response_model=CredentialReply)
    async def firebase(body: FirebaseLogin, request: Request):
        limited('login:' + (request.client.host if request.client else 'unknown'), 10)
        try: claims = await verifier.verify(body.identity_token, 'firebase')
        except IdentityUnavailable: raise HTTPException(503, 'identity_provider_unavailable') from None
        except Exception: raise HTTPException(401, 'invalid_identity') from None
        result = store.login('firebase:' + claims['sub'], claims['auth_time'])
        if not result: raise HTTPException(401, 'fresh_identity_required')
        return result

    @app.post('/v1/auth/refresh', response_model=CredentialReply)
    def refresh(body: Refresh, request: Request):
        limited('refresh:' + (request.client.host if request.client else 'unknown'), 30)
        result = store.refresh(body.refresh_token)
        if not result: raise HTTPException(401, 'invalid_refresh')
        return result

    @app.post('/v1/auth/logout', dependencies=[Depends(bearer)])
    def logout(request: Request):
        owner_for(request.headers.get('authorization'))
        store.logout(request.headers['authorization'][7:]); return {'logged_out':True}

    @app.delete('/v1/account', dependencies=[Depends(bearer)])
    def delete_account(request: Request):
        owner = owner_for(request.headers.get('authorization'))
        store.delete_user(owner)
        return {'deleted':True, 'scope':'inference identity, tokens and all derived session metadata; existing Firebase account deletion remains separate'}

    @app.post('/v1/sessions', status_code=201, response_model=CreatedReply, dependencies=[Depends(bearer)])
    def start_session(body: Start, request: Request):
        owner = owner_for(request.headers.get('authorization')); limited('sessions:' + owner, 10)
        if not app.state.model_ready: raise HTTPException(503, 'model_unavailable')
        if not getattr(recognizer, 'healthy', True): raise HTTPException(503, 'engine_stalled')
        if not app.state.retention_healthy: raise HTTPException(503, 'retention_unavailable')
        sid = store.create_session(owner, {'evidence':[], 'verse':None, 'source':intelligence.source})
        if not sid: raise HTTPException(429, 'session_capacity', headers={'Retry-After':'60'})
        return {'session_id':sid, 'next_sequence':0, 'websocket_path':f'/v1/sessions/{sid}/audio',
                'expires_in':settings.session_ttl, 'max_window_frames':128000, 'max_inflight':1,
                'audio_retention':'none', 'recovery_metadata_retention_seconds':settings.session_ttl}

    @app.get('/v1/sessions/{sid}', response_model=RecoveryReply, dependencies=[Depends(bearer)])
    def get_session(sid: str, request: Request):
        owner = owner_for(request.headers.get('authorization')); row = store.session(sid, owner)
        if not row: raise HTTPException(404, 'session_unavailable')
        return {'session_id':sid, 'next_sequence':row['seq']+1, 'end_frame':row['end_frame'],
                'last_event_id':row['event_id'], 'state':store.unpack(row['state'])}

    @app.delete('/v1/sessions/{sid}', dependencies=[Depends(bearer)])
    def close_session(sid: str, request: Request):
        owner = owner_for(request.headers.get('authorization')); store.close_session(sid, owner)
        return {'closed':True}

    @app.get('/v1/metrics', dependencies=[Depends(bearer)])
    def metrics(request: Request):
        owner_for(request.headers.get('authorization'))
        return dict(counters, inference_completed=recognizer.completed, inference_timeouts=recognizer.timeouts,
                    inference_seconds=recognizer.total_seconds, active_connections=len(leases))

    @app.websocket('/v1/sessions/{sid}/audio')
    async def audio(ws: WebSocket, sid: str):
        try:
            owner = owner_for(ws.headers.get('authorization'))
            if ws.headers.get('origin') is not None: raise HTTPException(403, 'native_transport_only')
            if not store.session(sid, owner): raise HTTPException(404, 'session_unavailable')
            if sid in leases: raise HTTPException(409, 'session_already_connected')
            if len(leases) >= settings.max_sessions: raise HTTPException(429, 'connection_capacity')
        except HTTPException:
            await ws.close(code=1008); return
        leases.add(sid)
        await ws.accept()
        try:
            while True:
                # Revocation/deletion applies to every window, including an
                # already-open socket. Token expiry requires reconnect/refresh.
                owner_for(ws.headers.get('authorization'))
                row = store.session(sid, owner)
                if not row: raise HTTPException(404, 'session_unavailable')
                message = await asyncio.wait_for(ws.receive_text(), 30)
                if len(message) > 2048: raise ValueError('header too large')
                header = AudioHeader.model_validate_json(message)
                raw = await asyncio.wait_for(ws.receive_bytes(), 10)
                if len(raw) > 512000: raise ValueError('frame too large')
                owner_for(ws.headers.get('authorization'))
                if not store.session(sid, owner): raise HTTPException(404, 'session_unavailable')
                samples = header.decode(raw); digest = header.digest(raw)
                if header.sequence == row['seq']:
                    if digest != row['frame_hash']: raise ValueError('replay content mismatch')
                    counters['replayed_windows'] += 1
                    await ws.send_json(store.unpack(row['result'])); continue
                if header.sequence != row['seq']+1 or header.start_frame > row['end_frame'] or header.end_frame <= row['end_frame']:
                    raise ValueError('discontinuous sequence')
                limited('audio:' + owner, 60)
                try: decoded = await recognizer.recognize(samples)
                except Busy:
                    counters['engine_busy'] += 1
                    await ws.send_json({'error':'engine_busy', 'retryable':True, 'sequence':header.sequence}); continue
                except InferenceDeadline:
                    counters['window_timeouts'] += 1
                    await ws.send_json({'error':'inference_timeout', 'retryable':True, 'sequence':header.sequence}); continue
                # No late write after logout/expiry/account deletion.
                owner_for(ws.headers.get('authorization'))
                row['decoded_state'] = store.unpack(row['state'])
                state, result, event_id = intelligence.process(sid, row, header, decoded)
                result = WindowReply.model_validate(result).model_dump()
                if not store.commit_window(sid, owner, row['seq'], header.sequence, header.end_frame, digest, state, result, event_id):
                    raise ValueError('session revision changed')
                counters['audio_windows'] += 1
                await ws.send_json(result)
        except WebSocketDisconnect: pass
        except (ValueError, ValidationError, HTTPException, asyncio.TimeoutError):
            counters['rejected_windows'] += 1
            with suppress(Exception): await ws.close(code=1008, reason='invalid_or_expired_session')
        except Exception:
            log.error('inference_session_failed')
            with suppress(Exception): await ws.close(code=1011, reason='engine_unavailable')
        finally: leases.discard(sid)

    return app


def application():
    return create_app(Settings.from_env())
