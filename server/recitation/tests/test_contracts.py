import json
from pathlib import Path
from noor_engine.protocol import AudioHeader
from noor_engine.contracts import WindowReply, WindowError


def test_public_contracts_expose_typed_auth_and_session_outputs(client):
    schema = client.get('/openapi.json').json()
    path = schema['paths']['/v1/sessions']['post']
    assert path['security'] == [{'HTTPBearer':[]}]
    assert path['responses']['201']['content']['application/json']['schema']['$ref'].endswith('/CreatedReply')
    assert schema['paths']['/v1/auth/firebase']['post']['responses']['200']['content']['application/json']['schema']['$ref'].endswith('/CredentialReply')
    assert path['responses']['422']['content']['application/json']['schema']['$ref'].endswith('/ErrorReply')
    assert 'access_token' in schema['components']['schemas']['CredentialReply']['properties']


def test_ws_contracts_pin_bounded_frames_events_and_confidence():
    header = AudioHeader.model_json_schema()
    response = WindowReply.model_json_schema()
    assert header['properties']['end_frame']['maximum'] == 28800000
    assert response['properties']['words']['maxItems'] == 160
    assert response['properties']['events']['maxItems'] == 400
    assert response['$defs']['HeardWord']['properties']['confidence']['minimum'] == .75
    assert WindowError.model_validate({'error':'engine_busy','retryable':True,'sequence':0})
