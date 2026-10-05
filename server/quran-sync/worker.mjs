// App-specific Content Sync gateway. No credentials or user progress leave this boundary.
const API = 'https://apis.quran.foundation/content';
const AUTH = 'https://oauth2.quran.foundation/oauth2/token';
const MAX_BYTES = 48 * 1024 * 1024;
const TOKENS = new WeakMap();
function json(value, status = 200) {
  return new Response(JSON.stringify(value), {status, headers: {
    'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store',
    'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer'}});
}
export function upstreamPath(url) {
  const u = new URL(url);
  if (u.pathname === '/v1/mushaf/sync') {
    const allowed = new Set(['bootstrap', 'sync_token', 'cursor', 'per_page']);
    if ([...u.searchParams.keys()].some(k => !allowed.has(k))) return null;
    const query = new URLSearchParams();
    for (const [key, value] of u.searchParams) {
      if (u.searchParams.getAll(key).length !== 1 || value.length > 8192) return null;
      if (key === 'bootstrap' && value !== 'true') return null;
      if (key === 'per_page' && !/^(?:[1-9]|[1-9][0-9]|100)$/.test(value)) return null;
      query.set(key, value);
    }
    if (query.has('bootstrap') && (query.has('sync_token') || query.has('cursor'))) return null;
    if (query.has('sync_token') && query.has('cursor')) return null;
    if (![...['bootstrap', 'sync_token', 'cursor']].some(k => query.has(k))) return null;
    query.set('resources', 'mushafs:1');
    if (!query.has('per_page')) query.set('per_page', '100');
    return '/api/v4/resources/sync?' + query;
  }
  if (u.pathname === '/v1/mushaf/snapshot' && !u.search) {
    return '/api/v4/resources/snapshots/mushafs/1';
  }
  return null;
}
async function readJSON(response) {
  if (!response.headers.get('content-type')?.includes('application/json')) throw new Error('Invalid upstream format');
  const reader = response.body?.getReader();
  if (!reader) throw new Error('Empty upstream body');
  const chunks = []; let length = 0;
  while (true) {
    const {value, done} = await reader.read(); if (done) break;
    length += value.byteLength;
    if (length > MAX_BYTES) { await reader.cancel(); throw new Error('Oversized upstream body'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.byteLength;}
  return JSON.parse(new TextDecoder().decode(bytes));
}
async function token(env, fetcher) {
  let state = TOKENS.get(env);
  if (state?.expires > Date.now()) return state.value;
  if (state?.pending) return state.pending;
  state = {expires: 0}; TOKENS.set(env, state);
  state.pending = (async () => {
    const authorization = 'Basic ' + btoa(env.QF_CLIENT_ID + ':' + env.QF_CLIENT_SECRET);
    const response = await fetcher(AUTH, {method: 'POST', redirect: 'error',
      signal: AbortSignal.timeout(15000), headers: {authorization,
        'content-type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=client_credentials&scope=content'});
    if (!response.ok) throw new Error('Upstream authentication unavailable');
    const result = await readJSON(response);
    if (typeof result.access_token !== 'string' || !Number.isFinite(result.expires_in) || result.expires_in <= 60)
      throw new Error('Invalid upstream token');
    state.value = result.access_token;
    state.expires = Date.now() + (result.expires_in - 60) * 1000;
    return state.value;
  })();
  try {return await state.pending;} finally {delete state.pending;}
}
export async function handle(request, env, fetcher = fetch) {
  if (request.method !== 'GET') return json({error: 'method_not_allowed'}, 405);
  const url = new URL(request.url);
  if (url.pathname === '/health' && !url.search) return json({service: 'noor-quran-sync', version: 1});
  const path = upstreamPath(url);
  if (!path) return json({error: 'not_found'}, 404);
  // Fail closed if secrets or the platform's abuse-control binding are missing.
  if (!env.QF_CLIENT_ID || !env.QF_CLIENT_SECRET || !env.SYNC_RATE_LIMITER)
    return json({error: 'service_not_configured'}, 503);
  const ip = request.headers.get('cf-connecting-ip');
  if (!ip) return json({error: 'request_not_supported'}, 403);
  const {success} = await env.SYNC_RATE_LIMITER.limit({key: ip});
  if (!success) return json({error: 'retry_later'}, 429);
  try {
    const accessToken = await token(env, fetcher);
    const response = await fetcher(API + path, {redirect: 'error',
      signal: AbortSignal.timeout(45000), headers: {
        'x-auth-token': accessToken, 'x-client-id': env.QF_CLIENT_ID,
        accept: 'application/json'}});
    if (response.status === 401) {TOKENS.delete(env); return json({error: 'upstream_unavailable'}, 503);}
    if (!response.ok) {
      // Return standard upstream recovery codes, never auth headers or diagnostics.
      if ([400, 404, 409, 410, 422].includes(response.status)) {
        const data = await readJSON(response);
        const code = data?.error?.code ?? data?.code;
        return json({error: typeof code === 'string' && /^[a-z_]{1,64}$/.test(code) ? code : 'sync_failed'}, response.status);
      }
      return json({error: 'upstream_unavailable'}, 503);
    }
    const data = await readJSON(response);
    return json(data);
  } catch {return json({error: 'upstream_unavailable'}, 503);}
}
export default {fetch(request, env) {return handle(request, env);}};
