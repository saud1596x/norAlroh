from dataclasses import dataclass, field
import os
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
from cryptography.fernet import Fernet


@dataclass(frozen=True)
class Settings:
    database_url: str = field(repr=False)
    data_key: str = field(repr=False)
    model_path: Path
    corpus_root: Path
    apple_audience: str = 'com.saud1596x.nooralruh'
    firebase_project: str = ''
    environment: str = 'production'
    max_sessions: int = 4
    inference_timeout: float = 20
    session_ttl: int = 3600
    token_ttl: int = 900
    cpu_threads: int = 2
    device: str = 'cpu'

    def __post_init__(self):
        Fernet(self.data_key.encode('ascii'))
        if self.environment not in {'production', 'local', 'test'}:
            raise ValueError('unsupported environment')
        if self.environment == 'production' and not self.database_url.startswith('postgresql+psycopg://'):
            raise ValueError('production requires PostgreSQL')
        if self.environment == 'production':
            query = parse_qs(urlsplit(self.database_url).query)
            if query.get('sslmode') != ['verify-full']:
                raise ValueError('production database requires certificate-verified TLS')
        if not 1 <= self.max_sessions <= 32 or not 1 <= self.inference_timeout <= 60:
            raise ValueError('invalid admission limits')
        if type(self.cpu_threads) is not int or not 1 <= self.cpu_threads <= 8:
            raise ValueError('invalid CPU allocation')
        if self.device not in {'cpu', 'cuda'}:
            raise ValueError('unsupported inference device')

    @classmethod
    def from_env(cls):
        return cls(database_url=os.environ['NOOR_DATABASE_URL'], data_key=os.environ['NOOR_DATA_KEY'],
                   model_path=Path(os.environ['NOOR_MODEL_PATH']), corpus_root=Path(os.environ['NOOR_CORPUS_ROOT']),
                   firebase_project=os.environ.get('NOOR_FIREBASE_PROJECT_ID', ''),
                   environment=os.environ.get('NOOR_ENVIRONMENT', 'production'),
                   max_sessions=int(os.environ.get('NOOR_MAX_SESSIONS', '4')),
                   cpu_threads=int(os.environ.get('NOOR_CPU_THREADS', '2')),
                   device=os.environ.get('NOOR_INFERENCE_DEVICE', 'cpu'))
