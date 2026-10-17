from pathlib import Path
import sys
import time
import pytest
import jwt
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from noor_engine.config import Settings
from noor_engine.api import create_app
from noor_engine.identity import IdentityVerifier

ROOT = Path(__file__).resolve().parents[3]


class ProtocolOnlyRecognizer:
    """Transport/fault tests only. Never used for acoustic acceptance."""
    model_id = 'TEST-ONLY-NOT-ASR'
    revision = 'test'
    pending = None
    completed = timeouts = 0
    total_seconds = 0
    def load(self): pass
    async def recognize(self, samples):
        return {'words':[], 'unresolved':False, 'inference_ms':0}


@pytest.fixture
def settings(tmp_path):
    return Settings(database_url='sqlite:///' + str(tmp_path/'noor.db'), data_key=Fernet.generate_key().decode(),
                    model_path=tmp_path/'missing-model', corpus_root=ROOT, environment='test', firebase_project='test-noor')


@pytest.fixture
def signed_identity(settings):
    # Cryptographically signed, local-test issuer key. No Apple account/token
    # or production JWKS overrides exist in runtime configuration.
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    verifier = IdentityVerifier(settings)
    async def local_key(url, kid):
        if kid != 'local-test': raise ValueError('unknown key')
        return key.public_key()
    verifier._key = local_key
    def sign(subject='test-subject', nonce=None, **changes):
        now = int(time.time())
        claims = dict(iss='https://appleid.apple.com', aud=settings.apple_audience, sub=subject, iat=now, exp=now+120)
        if nonce: claims['nonce'] = nonce
        claims.update(changes)
        return jwt.encode(claims, key, algorithm='RS256', headers={'kid':'local-test'})
    return verifier, sign


@pytest.fixture
def app(settings, signed_identity):
    return create_app(settings, recognizer=ProtocolOnlyRecognizer(), verifier=signed_identity[0])


@pytest.fixture
def client(app):
    with TestClient(app) as c: yield c


def login(client, sign, subject='test-subject'):
    import hashlib
    challenge = client.post('/v1/auth/apple/challenge').json()
    token = sign(subject=subject, nonce=hashlib.sha256(challenge['nonce'].encode()).hexdigest())
    result = client.post('/v1/auth/apple', json={'identity_token':token, 'challenge':challenge['challenge']})
    assert result.status_code == 200, result.text
    return result.json()


@pytest.fixture
def auth(client, signed_identity):
    return login(client, signed_identity[1])
