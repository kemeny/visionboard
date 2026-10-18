# visionboard-sync

Cloudflare Worker behind the app's `/api/sync/*`: cloud sync of boards and daily
reminder notifications. The free tier covers it comfortably.

- **D1** `visionboard`: boards and push subscriptions (schema in `migrations/`, already applied)
- **R2** `visionboard-images`: board images
- **Cron**, hourly: sends each subscriber their reminder at their chosen local hour

## Deploy

Deploys automatically through Cloudflare Workers Builds when `main` changes:
root directory `worker`, deploy command `npx wrangler deploy`.

The Next.js app finds the Worker through the `SYNC_API_URL` env var on Vercel
(e.g. `https://visionboard-sync.<subdomain>.workers.dev`). Without it, the sync
menu hides itself and the app works as before.

## Local

    npm install
    npx wrangler d1 migrations apply visionboard --local
    npm run dev              # Worker on :8787
    npm test                 # push encryption round-trip
    SYNC_API_URL=http://localhost:8787 pnpm dev   # in the repo root
