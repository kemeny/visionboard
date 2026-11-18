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

Deleting an account (`DELETE /api/sync/account`) first revokes the app's
Apple tokens through the Sign in with Apple REST API (App Review guideline
5.1.1(v)), then removes the account row and its backup. Boards stay under
their sync keys unless the app also deletes them. Sign-in sends Apple's
one-time authorization code, which the Worker exchanges for a refresh token
and keeps sealed like the backup, only so it can be revoked. If Apple can't
be reached the delete answers 502 and nothing is removed, so the app can try
again.

Session tokens carry the account's `created_at`, so a token issued before
the account was deleted stops working even if the same Apple user signs in
again. Sign-in also needs a nonce: the app puts SHA-256 of a random string in
the Apple request and sends the string itself, so an identity token can't be
replayed.

### Account endpoints

| Route | Auth | What it does |
| --- | --- | --- |
| `POST /api/sync/account/signin` `{identityToken, nonce, authorizationCode?}` | none | Verifies the Apple identity token (RS256 against Apple's published keys, issuer, audience `APPLE_BUNDLE_ID`, expiry, nonce), exchanges the authorization code for a refresh token, creates or updates the account, returns `{sessionToken, email, hasBackup}`. The session lasts 90 days. 30 sign-ins per address per hour. |
| `GET /api/sync/account/backup` | `Bearer <sessionToken>` | `{boards: [{name, syncKey}], email, updatedAt}`, or 409 `backup_unreadable` if `ACCOUNT_SECRET` changed (the app then uploads a new backup) |
| `PUT /api/sync/account/backup` `{boards}` | `Bearer <sessionToken>` | Replaces the backup list |
| `DELETE /api/sync/account` | `Bearer <sessionToken>` | Revokes the Apple tokens, then deletes the account and its backup |

Setup before the first deploy that uses accounts:

    pnpm wrangler secret put ACCOUNT_SECRET     # 32+ random characters, e.g. openssl rand -base64 48
    pnpm wrangler secret put APPLE_TEAM_ID      # the developer account's Team ID
    pnpm wrangler secret put APPLE_KEY_ID       # a Sign in with Apple key (Certificates, IDs & Profiles > Keys)
    pnpm wrangler secret put APPLE_PRIVATE_KEY  # that key's .p8 file, pasted whole
    pnpm wrangler d1 migrations apply visionboard --remote   # 0003_accounts.sql and 0004_account_apple_tokens.sql

Apply both migrations before deploying this Worker: the account routes read
the `apple_refresh_ciphertext` column. Without the three Apple secrets,
sign-in still works but nothing can be revoked on delete, which App Review
rejects, so set them before submitting the app.

`APPLE_BUNDLE_ID` defaults to `com.kemenystudio.visionboard`; set it as a var
only if the app's bundle id changes. Without `ACCOUNT_SECRET` the account
routes answer 503 and everything else works as before.

## Create with AI: Pro check and limits

`POST /api/sync/ai/board` needs the app's signed App Store transaction for an
active Pro plan in `X-VB-Pro` (`src/storekit.ts` checks the x5c chain up to
Apple Root CA - G3, the signature, bundle id, product and expiry) and answers
402 `pro_required` otherwise. Set the var `PRO_CHECK` to `off` only for local
testing with Xcode's StoreKit configuration file, whose transactions aren't
signed by Apple. TestFlight and App Store purchases are.

Rate limits are per address and overall, per clock hour. The overall caps
follow the Unsplash quota (`UNSPLASH_HOURLY_QUOTA`, default 5000): half for
photo searches (up to 9 per board) and half for download pings. Set it to 50
while the Unsplash app is still in demo mode.

The address comes from `X-Forwarded-For`, which only the web app's proxy may
set. Set the same random value as the Worker secret `PROXY_SECRET` and as
`SYNC_PROXY_SECRET` on Vercel: `proxy.ts` in the web app sends it in
`X-VB-Proxy`, and once `PROXY_SECRET` is set the Worker ignores
`X-Forwarded-For` on requests without it. Set Vercel first, then the Worker.

The Worker is still reachable at its workers.dev address, which `SYNC_API_URL`
points to today. To close that door, give the Worker a custom domain, point
`SYNC_API_URL` at it, then set `"workers_dev": false` and
`"preview_urls": false` in `wrangler.jsonc`.

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
    pnpm test               # push encryption, AI output checks and guard rails, account tokens and Apple revoke, StoreKit proofs
    SYNC_API_URL=http://localhost:8787 pnpm dev   # in the repo root
