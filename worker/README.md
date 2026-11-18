# visionboard-sync

Cloudflare Worker behind the app's `/api/sync/*`: cloud sync of boards and daily
reminder notifications. The free tier covers it comfortably.

- **D1** `visionboard`: boards and push subscriptions (schema in `migrations/`, already applied)
- **R2** `visionboard-images`: board images
- **Cron**, hourly: sends each subscriber their reminder at their chosen local hour,
  and clears expired AI rate-limit counters
- **AI board** (`src/ai.ts`): `POST /api/sync/ai/board` turns "tell me about your
  2027" into 6 to 9 goals with Unsplash photos, for the iOS app

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
    pnpm test               # push encryption round-trip and AI output checks
    SYNC_API_URL=http://localhost:8787 pnpm dev   # in the repo root
