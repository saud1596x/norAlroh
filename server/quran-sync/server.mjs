import http from 'node:http';
import {pathToFileURL} from 'node:url';
import {handle} from './worker.mjs';

// A single-instance gateway: global limits cannot be bypassed by forged IP headers.
export function createGateway({credentials = process.env, fetcher = fetch,
  now = Date.now, requestsPerMinute = 120, maxConcurrent = 4} = {}) {
  let active = 0, windowStart = now(), count = 0;
  const env = {
    QF_CLIENT_ID: credentials.QF_CLIENT_ID,
    QF_CLIENT_SECRET: credentials.QF_CLIENT_SECRET,
    SYNC_RATE_LIMITER: {limit: async () => {
      const time = now();
      if (time - windowStart >= 60000) {windowStart = time; count = 0;}
      return {success: ++count <= requestsPerMinute};
    }},
  };
  return http.createServer(async (req, res) => {
    res.setHeader('cache-control', 'no-store');
    res.setHeader('x-content-type-options', 'nosniff');
    const fail = (status, error) => {
      res.writeHead(status, {'content-type':'application/json; charset=utf-8'});
      res.end(JSON.stringify({error}));
    };
    // Only origin-form targets; do not trust Host or forwarded headers.
    if (!req.url?.startsWith('/') || req.url.startsWith('//') || req.url.length > 16384)
      return fail(400, 'invalid_request');
    if (req.method !== 'GET') return fail(405, 'method_not_allowed');
    if (active >= maxConcurrent) return fail(429, 'retry_later');
    active++;
    try {
      const request = new Request('https://noor-gateway.invalid' + req.url,
        {headers: {'cf-connecting-ip':'service-global'}});
      const response = await handle(request, env, fetcher);
      const bytes = Buffer.from(await response.arrayBuffer());
      if (!res.destroyed) {
        res.writeHead(response.status, Object.fromEntries(response.headers));
        res.end(bytes);
      }
    } catch {if (!res.headersSent && !res.destroyed) fail(503, 'service_unavailable');}
    finally {active--;}
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 10000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error('Invalid service port');
  const server = createGateway();
  server.requestTimeout = 60000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  server.listen(port, '0.0.0.0');
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}
