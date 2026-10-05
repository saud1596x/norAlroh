# Render deployment (staged, not deployed)

Create a single-instance Node Web Service from the publisher's repository:

- Root directory: `server/quran-sync`
- Build command: `npm test`
- Start command: `npm start`
- Health-check path: `/health`
- Node version: 22 or newer
- Secrets: `QF_CLIENT_ID`, `QF_CLIENT_SECRET` (production QF credentials)

No dependencies are installed. The HTTP adapter applies a process-wide limit of
120 content requests per minute and four concurrent requests. It ignores client
IP headers and never logs request data or OAuth tokens. This conservative global
limit can affect all readers at busy times; do not scale to multiple instances
without a shared limiter. `/health` is a liveness check, not proof of credentials
or valid Quran data. Native renderer migration is still incomplete.

Use the Free compute plan only to verify deployment and production snapshot
schema. Render documents that Free instances sleep after idle periods and are
not intended for production. Select a production compute plan only with an
approved budget. Do not add payment details, paid services, secret values to git,
or enable unreviewed automatic deployment as part of trial setup.

Deployment and secret transfer require the publisher's Render login and consent.
After deployment, test bootstrap and snapshot against production QF, then validate
the complete 604-page glyph/layout pairing before enabling it in the app.

Documentation:
- https://render.com/docs/deploy-node-express-app
- https://render.com/docs/configure-environment-variables
- https://render.com/docs/free
