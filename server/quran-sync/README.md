# Noor Quran Sync gateway

This is a staged service, not a deployed backend or a verified Mushaf renderer.
It only forwards production Content Sync for `mushafs:1`. It never bundles an
API snapshot into the app, exposes OAuth tokens, accepts arbitrary URLs, or
receives recordings, bookmarks, reflections, city selections, or user progress.

## Deployment requirements

Deploy this directory to the publisher's Cloudflare Workers account. Store the
existing QF production client ID and client secret as **Secrets**, never `vars`,
Swift resources, GitHub files, or logs. Deployment must retain the rate-limit
binding. The shared-IP limit is an abuse guard, not user authentication; it may
temporarily affect users behind a shared carrier address. The service is solely
for Noor Alruh's content experience, not a separately offered data API.

Before enabling the native integration, test a real production bootstrap and
snapshot, validate all returned page/line/glyph fields against the exact V2
font manifest, implement transactional local snapshot/update replacement,
apply deletions/invalidations, and only commit the sync token after all updates
validate. Refresh at least every seven days when connectivity permits. Retain
the last validated copy during connectivity failures.

No secrets have been added and no service has been deployed by this source.
The app renderer currently still uses QCF4 and must not consume V2 fonts until
its matched layout adapter and all-page native tests are complete.

Run boundary tests: `node --test worker.test.mjs`.

Provider documentation:
- https://api-docs.quran.foundation/docs/quickstart/manual-authentication/
- https://api-docs.quran.foundation/docs/tutorials/content-sync/getting-started/
- https://api-docs.quran.foundation/legal/developer-terms/
