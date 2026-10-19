"""Download integrity/TLS policy, not acoustic model acceptance."""
import hashlib
import io
import ssl

import pytest

import export_coreml


def test_download_uses_verified_public_roots_and_exact_bytes(tmp_path, monkeypatch):
    payload = b'pinned-public-asset'
    seen = []

    def response(url, *, timeout, context):
        assert url == 'https://example.invalid/model'
        assert timeout == 60
        assert context.verify_mode == ssl.CERT_REQUIRED
        assert context.check_hostname is True
        assert context.get_ca_certs()
        seen.append(context)
        return io.BytesIO(payload)

    monkeypatch.setattr(export_coreml.urllib.request, 'urlopen', response)
    target = tmp_path / 'asset'
    export_coreml.download('https://example.invalid/model', target,
                           hashlib.sha256(payload).hexdigest(), 100)
    assert target.read_bytes() == payload
    assert len(seen) == 1


def test_bad_certificate_is_not_retried_without_verification(tmp_path, monkeypatch):
    calls = []

    def response(*args, **kwargs):
        calls.append(kwargs)
        raise ssl.SSLCertVerificationError('untrusted test certificate')

    monkeypatch.setattr(export_coreml.urllib.request, 'urlopen', response)
    target = tmp_path / 'asset'
    with pytest.raises(ssl.SSLCertVerificationError):
        export_coreml.download('https://example.invalid/model', target, '0' * 64, 100)
    assert len(calls) == 1
    assert not target.exists()
    assert not target.with_suffix('.pending').exists()


@pytest.mark.parametrize('limit, message', [(2, 'size limit'), (100, 'bytes differ')])
def test_trusted_connection_cannot_authorize_large_or_changed_asset(tmp_path, monkeypatch, limit, message):
    monkeypatch.setattr(export_coreml.urllib.request, 'urlopen',
                        lambda *args, **kwargs: io.BytesIO(b'wrong-bytes'))
    target = tmp_path / 'asset'
    with pytest.raises(ValueError, match=message):
        export_coreml.download('https://example.invalid/model', target, '0' * 64, limit)
    assert not target.exists()
    assert not target.with_suffix('.pending').exists()
