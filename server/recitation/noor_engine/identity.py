"""Verify issuer, audience, signature, expiry and nonce; no client-selected JWKS."""
import asyncio
import time
import httpx
import jwt


class IdentityUnavailable(Exception): pass


class IdentityVerifier:
    def __init__(self, settings):
        self.settings = settings
        self.cache = {}
        self.lock = asyncio.Lock()

    async def _key(self, url, kid):
        if not isinstance(kid, str) or not 1 <= len(kid) <= 128: raise ValueError('invalid identity')
        async with self.lock:
            now = time.monotonic()
            keys, fetched = self.cache.get(url, ({}, -3601))
            if (kid not in keys and now - fetched >= 60) or now - fetched > 3600:
                try:
                    async with httpx.AsyncClient(timeout=5, follow_redirects=False, trust_env=False) as client:
                        async with client.stream('GET', url) as response:
                            response.raise_for_status()
                            raw = bytearray()
                            async for part in response.aiter_bytes():
                                raw.extend(part)
                                if len(raw) > 65536: raise ValueError('oversized key set')
                    import json
                    document = json.loads(raw)
                    keys = {v['kid']: jwt.PyJWK.from_dict(v).key for v in document['keys']
                            if v.get('kty') == 'RSA' and v.get('alg', 'RS256') == 'RS256' and v.get('use', 'sig') == 'sig'}
                    if not keys: raise ValueError('empty key set')
                except Exception: raise IdentityUnavailable() from None
                self.cache[url] = keys, now
            if kid not in keys: raise ValueError('unknown identity key')
            return keys[kid]

    async def verify(self, token, provider):
        if not isinstance(token, str) or not 1 <= len(token) <= 16384: raise ValueError('invalid identity')
        header = jwt.get_unverified_header(token)
        if header.get('alg') != 'RS256': raise ValueError('invalid identity algorithm')
        if provider == 'apple':
            issuer, audience = 'https://appleid.apple.com', self.settings.apple_audience
            url = 'https://appleid.apple.com/auth/keys'
        elif provider == 'firebase' and self.settings.firebase_project:
            issuer = 'https://securetoken.google.com/' + self.settings.firebase_project
            audience = self.settings.firebase_project
            url = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'
        else: raise ValueError('unsupported identity')
        key = await self._key(url, header.get('kid'))
        claims = jwt.decode(token, key, algorithms=['RS256'], audience=audience, issuer=issuer,
            options={'require': ['exp', 'iat', 'sub', 'aud', 'iss']}, leeway=10)
        if not isinstance(claims['sub'], str) or not 1 <= len(claims['sub']) <= 255: raise ValueError('invalid subject')
        if claims['exp']-claims['iat'] > 3900: raise ValueError('unsupported identity lifetime')
        if provider == 'firebase':
            if claims.get('firebase', {}).get('sign_in_provider') != 'apple.com':
                raise ValueError('Apple identity required')
            if not isinstance(claims.get('auth_time'), (int, float)) or claims['auth_time'] > time.time()+10:
                raise ValueError('invalid authentication time')
        return claims
