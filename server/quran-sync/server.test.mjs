import test from 'node:test';
import assert from 'node:assert/strict';
import {createGateway} from './server.mjs';

test('HTTP adapter keeps credentials private and applies a global limit across forged IPs', async t => {
  let calls = 0;
  const server = createGateway({credentials:{QF_CLIENT_ID:'id',QF_CLIENT_SECRET:'private'},
    requestsPerMinute:1, fetcher:async url => {
      calls++;
      return Response.json(url.includes('/oauth2/token')
        ? {access_token:'token-private',expires_in:3600} : {records:[]});
    }});
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => {server.close(resolve); server.closeAllConnections();}));
  const base = `http://127.0.0.1:${server.address().port}`;
  const first = await fetch(base+'/v1/mushaf/snapshot', {headers:{'x-forwarded-for':'one'}});
  assert.equal(first.status,200);
  assert.equal(await first.text(),'{"records":[]}');
  const second = await fetch(base+'/v1/mushaf/snapshot', {headers:{'x-forwarded-for':'two'}});
  assert.equal(second.status,429);
  assert.equal(calls,2);
  assert.equal((await fetch(base+'/health')).status,200);
  assert.equal((await fetch(base+'/health',{method:'POST'})).status,405);
});
