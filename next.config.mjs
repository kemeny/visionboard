/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  // Sync and reminders live in a Cloudflare Worker (see worker/). Proxying keeps
  // it same-origin, so the browser never needs the Worker's address or CORS.
  // PostHog's batch endpoint needs its trailing slash kept
  skipTrailingSlashRedirect: true,
  async rewrites() {
    // Analytics go through our own domain so ad blockers don't drop them
    const rules = [
      { source: '/ingest/static/:path*', destination: 'https://us-assets.i.posthog.com/static/:path*' },
      { source: '/ingest/:path*', destination: 'https://us.i.posthog.com/:path*' },
    ]
    const target = process.env.SYNC_API_URL
    if (target) {
      rules.push({ source: '/api/sync/:path*', destination: `${target.replace(/\/$/, '')}/api/sync/:path*` })
    }
    return rules
  },
}

export default nextConfig
