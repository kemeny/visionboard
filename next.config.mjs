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
  async rewrites() {
    const target = process.env.SYNC_API_URL
    if (!target) return []
    return [{ source: '/api/sync/:path*', destination: `${target.replace(/\/$/, '')}/api/sync/:path*` }]
  },
}

export default nextConfig
