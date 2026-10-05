import test from 'node:test';
import assert from 'node:assert/strict';
import {handle, upstreamPath} from './worker.mjs';
const request = path => new Request('https://app.example' + path, {headers: {'cf-connecting-ip': '192.0.2.1'}});
test('only the matched Mushaf resource can be requested', () => {
  assert.equal(upstreamPath('https://app.example/v1/mushaf/snapshot'), '/api/v4/resources/snapshots/mushafs/1');
  for (const path of ['/v1/mushaf/snapshot?url=https://evil.example', '/oauth2/token',
    '/v1/mushaf/sync?resources=translations:19&bootstrap=true',
    '/v1/mushaf/sync?bootstrap=true&sync_token=x', '/v1/mushaf/sync?cursor=a&cursor=b'])
    assert.equal(upstreamPath('https://app.example' + path), null);
});
test('missing configuration and rate limits prevent upstream calls', async () => {
  let calls = 0; const fetcher = () => {calls++; throw Error('must not fetch');};
  assert.equal((await handle(request('/v1/mushaf/snapshot'), {}, fetcher)).status, 503);
  assert.equal((await handle(request('/v1/mushaf/snapshot'), {QF_CLIENT_ID:'id', QF_CLIENT_SECRET:'secret',
    SYNC_RATE_LIMITER:{limit:async () => ({success:false})}}, fetcher)).status, 429);
  assert.equal(calls, 0);
});
test('credentials stay server-side and redirects cannot leak them', async () => {
  const calls=[]; const env={QF_CLIENT_ID:'id', QF_CLIENT_SECRET:'private',
    SYNC_RATE_LIMITER:{limit:async () => ({success:true})}};
  const fetcher=async (url, options) => {
    calls.push({url,options});
    return Response.json(url.includes('/oauth2/token') ? {access_token:'token-private', expires_in:3600}
      : {resource_group:'mushafs', resource_id:1, records:[]});
  };
  const response=await handle(request('/v1/mushaf/snapshot'), env, fetcher);
  assert.equal(response.status,200);
  const body=await response.text(); assert.ok(!body.includes('private'));
  assert.equal(calls.length,2);
  assert.equal(calls[1].options.redirect,'error');
  assert.equal(calls[1].url,'https://apis.quran.foundation/content/api/v4/resources/snapshots/mushafs/1');
  assert.equal(calls[1].options.headers['x-auth-token'],'token-private');
  await handle(request('/v1/mushaf/snapshot'), env, fetcher);
  assert.equal(calls.filter(x=>x.url.includes('/oauth2/token')).length,1);
});
