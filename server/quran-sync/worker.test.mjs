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

const configured = () => ({QF_CLIENT_ID:'id', QF_CLIENT_SECRET:'private-secret',
  SYNC_RATE_LIMITER:{limit:async () => ({success:true})}});
const authResponse = () => Response.json({access_token:'private-token', expires_in:3600});
async function assertSafeFailure(response) {
  assert.equal(response.status,503);
  assert.equal(await response.text(),'{"error":"upstream_unavailable"}');
  assert.equal(response.headers.get('cache-control'),'no-store');
}

test('a failed rate limiter fails closed without making upstream calls', async () => {
  const env=configured(); let calls=0;
  env.SYNC_RATE_LIMITER.limit=async () => {throw Error('private-secret diagnostic');};
  await assertSafeFailure(await handle(request('/v1/mushaf/snapshot'),env,
    async () => {calls++; throw Error('must not fetch');}));
  assert.equal(calls,0);
});

test('oversized streamed upstream JSON is cancelled and never returned', async () => {
  const env=configured(); let emitted=0, cancelled=false;
  const stream=new ReadableStream({
    pull(controller) {emitted++; controller.enqueue(new Uint8Array(1024*1024));},
    cancel() {cancelled=true;},
  });
  await assertSafeFailure(await handle(request('/v1/mushaf/snapshot'),env,
    async url => url.includes('/oauth2/token') ? authResponse()
      : new Response(stream,{headers:{'content-type':'application/json'}})));
  assert.equal(cancelled,true);
  assert.ok(emitted>=49 && emitted<=50,'48MiB bound must stop consumption, allowing one queued chunk');
});

test('malformed JSON and unexpected content types fail safely', async () => {
  for (const [body,type] of [['{"private-token":','application/json'],
    ['private-secret upstream page','text/html']]) {
    await assertSafeFailure(await handle(request('/v1/mushaf/snapshot'),configured(),
      async url => url.includes('/oauth2/token') ? authResponse()
        : new Response(body,{headers:{'content-type':type}})));
  }
});

test('upstream fetch timeout uses an abort signal and returns a safe failure', async t => {
  // Accelerate the real AbortSignal timer; the production duration remains
  // asserted and unchanged. No production endpoint or wall-clock45s wait.
  const timeout=AbortSignal.timeout.bind(AbortSignal); const durations=[];
  t.mock.method(AbortSignal,'timeout',milliseconds => {
    durations.push(milliseconds); return timeout(10);
  });
  const keepingEventLoopAlive=setTimeout(() => {},1000);
  try {
    await assertSafeFailure(await handle(request('/v1/mushaf/snapshot'),configured(),
      async (url,options) => {
        if (url.includes('/oauth2/token')) return authResponse();
        assert.equal(options.redirect,'error');
        return new Promise((resolve,reject) => {
          options.signal.addEventListener('abort',() => reject(options.signal.reason),{once:true});
        });
      }));
    assert.deepEqual(durations,[15000,45000]);
  } finally {clearTimeout(keepingEventLoopAlive);}
});

test('authentication failure and invalid token payload never reach content API', async () => {
  for (const response of [new Response('private-secret',{status:401}),
    Response.json({access_token:'private-token',expires_in:1})]) {
    let contentCalls=0;
    await assertSafeFailure(await handle(request('/v1/mushaf/snapshot'),configured(),
      async url => {
        if (url.includes('/oauth2/token')) return response;
        contentCalls++; throw Error('must not fetch');
      }));
    assert.equal(contentCalls,0);
  }
});
