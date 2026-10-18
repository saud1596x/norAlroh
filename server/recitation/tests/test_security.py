import hashlib
import time
import pytest
from sqlalchemy import select
from noor_engine.storage import credentials, sessions, schema
from noor_engine.config import Settings
from conftest import login


def test_apple_nonce_replay_wrong_audience_and_expiry_fail_closed(client, signed_identity):
    sign = signed_identity[1]
    challenge = client.post('/v1/auth/apple/challenge').json()
    nonce = hashlib.sha256(challenge['nonce'].encode()).hexdigest()
    body = {'identity_token':sign(nonce=nonce), 'challenge':challenge['challenge']}
    assert client.post('/v1/auth/apple', json=body).status_code == 200
    assert client.post('/v1/auth/apple', json=body).status_code == 401
    for changes in [{'aud':'other-app'}, {'iss':'https://untrusted.invalid'}, {'exp':int(time.time())-60}]:
        challenge = client.post('/v1/auth/apple/challenge').json()
        body = {'identity_token':sign(nonce=hashlib.sha256(challenge['nonce'].encode()).hexdigest(), **changes), 'challenge':challenge['challenge']}
        assert client.post('/v1/auth/apple', json=body).status_code == 401


def test_refresh_rotation_and_reuse_revoke_entire_family(client, auth):
    newer = client.post('/v1/auth/refresh', json={'refresh_token':auth['refresh_token']})
    assert newer.status_code == 200
    assert client.get('/v1/metrics', headers={'Authorization':'Bearer '+auth['access_token']}).status_code == 401
    token = newer.json()['access_token']
    assert client.get('/v1/metrics', headers={'Authorization':'Bearer '+token}).status_code == 200
    assert client.post('/v1/auth/refresh', json={'refresh_token':auth['refresh_token']}).status_code == 401
    assert client.get('/v1/metrics', headers={'Authorization':'Bearer '+token}).status_code == 401


def test_owner_isolation_deletion_revocation_and_no_raw_token_storage(client, app, auth, signed_identity):
    headers = {'Authorization':'Bearer '+auth['access_token']}
    session = client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'}).json()['session_id']
    other = login(client, signed_identity[1], 'other-subject')
    other_headers = {'Authorization':'Bearer '+other['access_token']}
    assert client.get('/v1/sessions/'+session, headers=other_headers).status_code == 404
    client.delete('/v1/sessions/'+session, headers=other_headers)
    assert client.get('/v1/sessions/'+session, headers=headers).status_code == 200
    with app.state.store.engine.connect() as c:
        tokens = c.execute(select(credentials)).mappings().all()
        assert auth['access_token'] not in repr(tokens) and auth['refresh_token'] not in repr(tokens)
        encrypted = c.execute(select(sessions.c.state)).scalar_one()
        assert 'evidence' not in encrypted
    assert client.delete('/v1/account', headers=headers).status_code == 200
    assert client.get('/v1/sessions/'+session, headers=headers).status_code == 401
    assert client.post('/v1/auth/refresh', json={'refresh_token':auth['refresh_token']}).status_code == 401
    with app.state.store.engine.connect() as c: assert not c.execute(select(sessions)).all()


def test_unknown_fields_and_oversize_identity_never_echo_secrets(client):
    secret = 'PRIVATE-TOKEN-CONTENT'
    response = client.post('/v1/auth/apple', json={'identity_token':secret, 'challenge':'x', 'extra':secret})
    assert response.status_code == 422 and secret not in response.text
    response = client.post('/v1/auth/apple', content=b'x'*25000, headers={'Content-Type':'application/json'})
    assert response.status_code == 413
    assert response.headers['cache-control'] == 'no-store'


def test_expired_session_is_purged_and_schema_version_fails_closed(client, app, auth, signed_identity):
    headers = {'Authorization':'Bearer '+auth['access_token']}
    sid = client.post('/v1/sessions', headers=headers, json={'consent':'transient-audio-encrypted-recovery-1h'}).json()['session_id']
    clock = app.state.store.clock
    app.state.store.clock = lambda:clock()+4000
    app.state.store.cleanup()
    app.state.store.clock = clock
    assert client.get('/v1/sessions/'+sid, headers=headers).status_code == 401
    fresh = login(client, signed_identity[1])
    headers = {'Authorization':'Bearer '+fresh['access_token']}
    assert client.get('/v1/sessions/'+sid, headers=headers).status_code == 404
    with app.state.store.engine.begin() as c: c.execute(schema.update().values(version=99))
    with pytest.raises(RuntimeError): app.state.store.migrate()


def test_production_requires_database_tls_and_external_key(settings):
    with pytest.raises(ValueError):
        Settings(database_url='sqlite://', data_key=settings.data_key, model_path=settings.model_path,
                 corpus_root=settings.corpus_root)


def test_rate_limit_enforced_without_trusting_forwarded_header(client):
    results = [client.post('/v1/auth/apple/challenge', headers={'X-Forwarded-For':str(i)}).status_code for i in range(12)]
    assert results[:10] == [200]*10 and results[10:] == [429]*2


def test_firebase_apple_bridge_verifies_provider_and_blocks_old_identity_after_deletion(client, signed_identity):
    sign = signed_identity[1]
    now = int(time.time())
    def token(provider='apple.com'):
        return sign(iss='https://securetoken.google.com/test-noor', aud='test-noor',
                    auth_time=now, firebase={'sign_in_provider':provider})
    assert client.post('/v1/auth/firebase', json={'identity_token':token('password')}).status_code == 401
    minted = client.post('/v1/auth/firebase', json={'identity_token':token()})
    assert minted.status_code == 200
    headers = {'Authorization':'Bearer '+minted.json()['access_token']}
    assert client.delete('/v1/account', headers=headers).status_code == 200
    assert client.post('/v1/auth/firebase', json={'identity_token':token()}).status_code == 401


def test_readiness_fails_closed_when_retention_cleanup_unhealthy(client, app, auth):
    app.state.retention_healthy = False
    assert client.get('/health/live').status_code == 200
    assert client.get('/health/ready').status_code == 503
    assert client.post('/v1/sessions', headers={'Authorization':'Bearer '+auth['access_token']},
        json={'consent':'transient-audio-encrypted-recovery-1h'}).status_code == 503


def test_stalled_compute_cannot_advertise_readiness_or_admit_new_session(client, app, auth):
    app.state.recognizer.healthy = False
    assert client.get('/health/live').status_code == 200
    assert client.get('/health/ready').status_code == 503
    assert client.post('/v1/sessions',headers={'Authorization':'Bearer '+auth['access_token']},
        json={'consent':'transient-audio-encrypted-recovery-1h'}).status_code == 503


def test_identity_provider_network_failure_is_not_reported_as_bad_user_identity(client, app):
    from noor_engine.identity import IdentityUnavailable
    async def unavailable(token, provider): raise IdentityUnavailable()
    app.state.verifier.verify = unavailable
    response = client.post('/v1/auth/firebase', json={'identity_token':'local-test-no-user-token'})
    assert response.status_code == 503 and response.json()['detail'] == 'identity_provider_unavailable'


def test_repeated_login_does_not_leave_unbounded_credential_families(client, app):
    tokens = [app.state.store.login('bounded-local-test-principal') for _ in range(6)]
    assert app.state.store.authenticate(tokens[0]['access_token']) is None
    assert all(app.state.store.authenticate(t['access_token']) for t in tokens[1:])


def test_concurrent_first_rate_requests_cannot_collide_or_exceed_cap(settings):
    from concurrent.futures import ThreadPoolExecutor
    from noor_engine.storage import Store
    store = Store(settings, clock=lambda:100.0)
    store.migrate()
    try:
        with ThreadPoolExecutor(max_workers=8) as executor:
            accepted = list(executor.map(lambda _:store.limit('same-first-bucket',maximum=7),range(32)))
        assert sum(accepted) == 7
        assert store.limit('same-first-bucket',maximum=7) is False
        store.clock = lambda:160.0
        assert store.limit('same-first-bucket',maximum=7) is True
    finally: store.engine.dispose()
