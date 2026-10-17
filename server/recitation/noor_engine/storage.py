"""Durable ownership, rotated credentials and encrypted short-lived events.

No audio samples, email or Apple token are stored. Derived recognition results
are encrypted, limited to session recovery for one hour, and deleted on close.
One service process is the initial supported topology. Do not horizontally scale
without distributed model admission and socket leases.
"""
from contextlib import contextmanager
import hashlib
import hmac
import json
import secrets
import time
from cryptography.fernet import Fernet
from sqlalchemy import (create_engine, MetaData, Table, Column, String, Integer, Float, Text,
                        ForeignKey, select, update, delete, event, func)
from sqlalchemy.pool import StaticPool

metadata = MetaData()
schema = Table('schema_version', metadata, Column('id', Integer, primary_key=True), Column('version', Integer, nullable=False))
users = Table('users', metadata, Column('id', String(64), primary_key=True), Column('created', Float, nullable=False))
deletions = Table('account_deletions', metadata, Column('owner', String(64), primary_key=True),
                  Column('deleted_at', Float, nullable=False))
credentials = Table('credentials', metadata, Column('digest', String(64), primary_key=True),
    Column('owner', String(64), ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
    Column('family', String(64), nullable=False), Column('kind', String(12), nullable=False),
    Column('expires', Float, nullable=False), Column('used', Integer, nullable=False, default=0))
challenges = Table('challenges', metadata, Column('id', String(64), primary_key=True),
    Column('nonce_hash', String(64), nullable=False), Column('expires', Float, nullable=False))
sessions = Table('recitation_sessions', metadata, Column('id', String(64), primary_key=True),
    Column('owner', String(64), ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
    Column('expires', Float, nullable=False), Column('seq', Integer, nullable=False, default=-1),
    Column('event_id', Integer, nullable=False, default=0), Column('end_frame', Integer, nullable=False, default=0),
    Column('frame_hash', String(64)), Column('state', Text, nullable=False),
    Column('result', Text), Column('closed', Integer, nullable=False, default=0))
buckets = Table('rate_buckets', metadata, Column('key', String(64), primary_key=True),
    Column('reset', Float, nullable=False), Column('count', Integer, nullable=False))


class Store:
    def __init__(self, settings, clock=time.time):
        self.settings, self.clock = settings, clock
        self.cipher = Fernet(settings.data_key.encode('ascii'))
        # Domain-separated pseudonyms survive restarts with the configured key.
        self.key = hashlib.sha256(settings.data_key.encode()).digest()
        args = {'connect_args': {'check_same_thread': False}} if settings.database_url.startswith('sqlite') else {}
        if settings.database_url == 'sqlite://': args['poolclass'] = StaticPool
        self.engine = create_engine(settings.database_url, pool_pre_ping=True, **args)
        if settings.database_url.startswith('sqlite'):
            @event.listens_for(self.engine, 'connect')
            def foreign_keys(connection, _): connection.execute('PRAGMA foreign_keys=ON')

    def migrate(self):
        # Explicit startup migration: schema version cannot be silently ignored.
        metadata.create_all(self.engine)
        with self.engine.begin() as c:
            version = c.execute(select(schema.c.version).where(schema.c.id == 1)).scalar_one_or_none()
            if version is None: c.execute(schema.insert().values(id=1, version=1))
            elif version != 1: raise RuntimeError('unsupported database schema')

    def pack(self, value): return self.cipher.encrypt(json.dumps(value, separators=(',', ':'), allow_nan=False).encode()).decode()
    def unpack(self, value): return json.loads(self.cipher.decrypt(value.encode()))
    def pseudonym(self, text): return hmac.new(self.key, text.encode(), hashlib.sha256).hexdigest()
    @staticmethod
    def digest(token): return hashlib.sha256(token.encode()).hexdigest()

    def cleanup(self):
        now = self.clock()
        with self.engine.begin() as c:
            for table in [sessions, challenges]: c.execute(delete(table).where(table.c.expires < now))
            # Keep used refresh digests until family expiry for reuse detection.
            c.execute(delete(credentials).where(credentials.c.expires < now))
            c.execute(delete(buckets).where(buckets.c.reset < now))
            c.execute(delete(deletions).where(deletions.c.deleted_at < now-31*86400))
            # Inference-only identities have no reading profile. Purge inactive
            # pseudonyms once no access/refresh/session can reference them.
            c.execute(delete(users).where(users.c.created < now-31*86400,
                ~users.c.id.in_(select(credentials.c.owner)), ~users.c.id.in_(select(sessions.c.owner))))

    def limit(self, key, maximum=30, seconds=60):
        key = self.pseudonym('rate:' + key); now = self.clock()
        with self.engine.begin() as c:
            # Atomic increment is safe across requests; service is single process.
            row = c.execute(select(buckets).where(buckets.c.key == key).with_for_update()).mappings().first()
            if not row: c.execute(buckets.insert().values(key=key, reset=now + seconds, count=1)); return True
            if row['reset'] < now:
                c.execute(update(buckets).where(buckets.c.key == key).values(reset=now + seconds, count=1)); return True
            if row['count'] >= maximum: return False
            c.execute(update(buckets).where(buckets.c.key == key).values(count=buckets.c.count + 1)); return True

    def challenge(self):
        challenge, nonce = secrets.token_urlsafe(24), secrets.token_urlsafe(32)
        with self.engine.begin() as c:
            c.execute(challenges.insert().values(id=challenge, nonce_hash=self.digest(nonce), expires=self.clock()+300))
        return {'challenge': challenge, 'nonce': nonce, 'expires_in': 300}

    def consume_challenge(self, challenge, nonce_hash):
        with self.engine.begin() as c:
            result = c.execute(delete(challenges).where(challenges.c.id == challenge,
                challenges.c.nonce_hash == nonce_hash, challenges.c.expires > self.clock()))
            return result.rowcount == 1

    def _issue(self, c, owner, family):
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
        now = self.clock()
        for token, kind, expires in [(access, 'access', now+self.settings.token_ttl), (refresh, 'refresh', now+30*86400)]:
            c.execute(credentials.insert().values(digest=self.digest(token), owner=owner, family=family, kind=kind, expires=expires, used=0))
        return {'access_token': access, 'refresh_token': refresh, 'expires_in': self.settings.token_ttl, 'token_type': 'Bearer'}

    def login(self, verified_subject, authenticated_at=None):
        owner = self.pseudonym('subject:' + verified_subject)
        with self.engine.begin() as c:
            deleted_at = c.execute(select(deletions.c.deleted_at).where(deletions.c.owner == owner)).scalar_one_or_none()
            if deleted_at is not None:
                if authenticated_at is None or authenticated_at <= deleted_at: return None
                c.execute(delete(deletions).where(deletions.c.owner == owner))
            if not c.execute(select(users.c.id).where(users.c.id == owner)).first():
                c.execute(users.insert().values(id=owner, created=self.clock()))
            families = c.execute(select(credentials.c.family, func.max(credentials.c.expires).label('latest'))
                .where(credentials.c.owner == owner).group_by(credentials.c.family).order_by('latest')).all()
            for old_family, _ in families[:max(0, len(families)-4)]:
                c.execute(delete(credentials).where(credentials.c.family == old_family))
            return self._issue(c, owner, secrets.token_urlsafe(24))

    def authenticate(self, token):
        with self.engine.connect() as c:
            return c.execute(select(credentials.c.owner).where(credentials.c.digest == self.digest(token),
                credentials.c.kind == 'access', credentials.c.used == 0, credentials.c.expires > self.clock())).scalar_one_or_none()

    def refresh(self, token):
        with self.engine.begin() as c:
            row = c.execute(select(credentials).where(credentials.c.digest == self.digest(token),
                credentials.c.kind == 'refresh', credentials.c.expires > self.clock()).with_for_update()).mappings().first()
            if not row: return None
            if row['used']:
                c.execute(delete(credentials).where(credentials.c.family == row['family'])); return None
            changed = c.execute(update(credentials).where(credentials.c.digest == row['digest'], credentials.c.used == 0).values(used=1))
            if changed.rowcount != 1: return None
            c.execute(delete(credentials).where(credentials.c.family == row['family'], credentials.c.kind == 'access'))
            return self._issue(c, row['owner'], row['family'])

    def logout(self, token):
        with self.engine.begin() as c:
            family = c.execute(select(credentials.c.family).where(credentials.c.digest == self.digest(token))).scalar_one_or_none()
            if family: c.execute(delete(credentials).where(credentials.c.family == family))

    def delete_user(self, owner):
        with self.engine.begin() as c:
            c.execute(delete(deletions).where(deletions.c.owner == owner))
            c.execute(deletions.insert().values(owner=owner, deleted_at=self.clock()))
            c.execute(delete(users).where(users.c.id == owner))

    def create_session(self, owner, initial):
        self.cleanup()
        with self.engine.begin() as c:
            c.execute(select(users.c.id).where(users.c.id == owner).with_for_update()).first()
            own = c.execute(select(sessions.c.id).where(sessions.c.owner == owner, sessions.c.closed == 0)).all()
            if len(own) >= 1: return None
            sid = secrets.token_urlsafe(24)
            c.execute(sessions.insert().values(id=sid, owner=owner, expires=self.clock()+self.settings.session_ttl,
                seq=-1, event_id=0, end_frame=0, state=self.pack(initial), closed=0))
        return sid

    def session(self, sid, owner):
        with self.engine.connect() as c:
            row = c.execute(select(sessions).where(sessions.c.id == sid, sessions.c.owner == owner,
                sessions.c.expires > self.clock(), sessions.c.closed == 0)).mappings().first()
            return dict(row) if row else None

    def commit_window(self, sid, owner, previous_seq, seq, end_frame, digest, state, result, event_id):
        with self.engine.begin() as c:
            # Compare-and-swap also prevents a late cancelled result overwriting
            # a closed, deleted, expired or already advanced session.
            row = c.execute(update(sessions).where(sessions.c.id == sid, sessions.c.owner == owner,
                sessions.c.seq == previous_seq, sessions.c.closed == 0, sessions.c.expires > self.clock()).values(
                    seq=seq, end_frame=end_frame, frame_hash=digest, state=self.pack(state),
                    result=self.pack(result), event_id=event_id))
            return row.rowcount == 1

    def close_session(self, sid, owner):
        with self.engine.begin() as c:
            # Purge derived metadata too; close does not retain a transcript.
            c.execute(delete(sessions).where(sessions.c.id == sid, sessions.c.owner == owner))
