# visionboard-sync

Cloudflare Worker behind the app's `/api/sync/*`: cloud sync of boards and daily
reminder notifications. The free tier covers it comfortably.

- **D1** `visionboard`: boards and push subscriptions (schema in `migrations/`, already applied)
- **R2** `visionboard-images`: board images
- **Cron**, hourly: sends each subscriber their reminder at their chosen local hour,
  and clears expired AI rate-limit counters
- **AI board** (`src/ai.ts`): `POST /api/sync/ai/board` turns "tell me about your
  2027" into 6 to 9 goals with Unsplash photos, for the iOS app
- **Accounts** (optional, Sign in with Apple from the iOS app): back up the list of a person's boards so a new device can reconnect them

## AI board

`POST /api/sync/ai/board` with header `X-VB-Client: ios` and body
`{"prompt": "...", "lang": "en" | "es", "count": 8}` (prompt up to 600
characters, count 6 to 9). Claude (`claude-haiku-5-5`, structured JSON output)
writes short first-person goals plus an English photo search for each, and
Unsplash finds one portrait photo per goal. Returns
`{"items": [{"text", "imageUrl", "photographer", "photographerUrl", "unsplashDownloadUrl"}]}`;
the photo fields are `null` when no photo was found.

`POST /api/sync/ai/unsplash-download` with `{"url": "<unsplashDownloadUrl>"}`
triggers Unsplash's download tracking, which their API guidelines require
whenever a photo is actually used. The app calls it for each photo it adds.

Limits: 10 generations per caller per hour and 400 overall per hour, counted
in the `ai_rate` table (migration `0002_ai_rate.sql`, keyed by a hash of the
address). Errors are `{"error": code}`: `client_not_allowed` (403),
`ai_unavailable` (503, a secret is missing), `rate_limited` (429),
`invalid_prompt` (400), `refused`, `invalid_output`, `ai_busy`, `ai_failed`.

Secrets, set once per environment:

    pnpm wrangler secret put ANTHROPIC_API_KEY
    pnpm wrangler secret put UNSPLASH_ACCESS_KEY
    pnpm wrangler d1 migrations apply visionboard --remote   # adds ai_rate

For local runs put both in `worker/.dev.vars` (git-ignored).

## Security note

Boards are keyed by the SHA-256 of their sync key, and the key itself is never
stored for a board. The one exception is signed-in accounts: for those people
only, the server now stores their boards' names and sync keys so it can give
them back on a new device. That list is encrypted at rest with AES-256-GCM,
using a key derived (HKDF-SHA-256) from the `ACCOUNT_SECRET` secret and the
account id, so a copy of the database alone reveals no sync key. Anyone with
both the database and `ACCOUNT_SECRET` could read them, so keep that secret
out of the repo and rotate it only together with a plan for existing backups
(rotating makes every stored backup unreadable). People who never sign in are
unaffected.

Deleting an account (`DELETE /api/sync/account`) removes the account row and
its backup. Boards stay under their sync keys unless the app also deletes them.

### Account endpoints

| Route | Auth | What it does |
| --- | --- | --- |
| `POST /api/sync/account/signin` `{identityToken}` | none | Verifies the Apple identity token (RS256 against Apple's published keys, issuer, audience `APPLE_BUNDLE_ID`, expiry), creates or updates the account, returns `{sessionToken, email, hasBackup}`. The session lasts 90 days. |
| `GET /api/sync/account/backup` | `Bearer <sessionToken>` | `{boards: [{name, syncKey}], email, updatedAt}` |
| `PUT /api/sync/account/backup` `{boards}` | `Bearer <sessionToken>` | Replaces the backup list |
| `DELETE /api/sync/account` | `Bearer <sessionToken>` | Deletes the account and its backup |

Setup before the first deploy that uses accounts:

    pnpm wrangler secret put ACCOUNT_SECRET     # 32+ random characters, e.g. openssl rand -base64 48
    pnpm wrangler d1 migrations apply visionboard --remote   # adds the accounts table (0003_accounts.sql)

`APPLE_BUNDLE_ID` defaults to `com.kemenystudio.visionboard`; set it as a var
only if the app's bundle id changes. Without `ACCOUNT_SECRET` the account
routes answer 503 and everything else works as before.

## Deploy

Deploys automatically through Cloudflare Workers Builds when `main` changes:
root directory `worker`, deploy command `npx wrangler deploy`.

The Next.js app finds the Worker through the `SYNC_API_URL` env var on Vercel
(e.g. `https://visionboard-sync.<subdomain>.workers.dev`). Without it, the sync
menu hides itself and the app works as before.

## Local

    pnpm install
    pnpm wrangler d1 migrations apply visionboard --local
    pnpm dev                 # Worker on :8787
    pnpm test               # push encryption round-trip, AI output checks, account tokens and backup encryption
    SYNC_API_URL=http://localhost:8787 pnpm dev   # in the repo root
