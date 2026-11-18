import { NextResponse, type NextRequest } from "next/server"

// Requests to the sync Worker (rewritten in next.config.mjs) carry a shared
// secret, so the Worker can trust the X-Forwarded-For address the proxy adds
// and ignore one sent straight to it. The secret is SYNC_PROXY_SECRET here and
// PROXY_SECRET on the Worker (see worker/README.md).
export function proxy(request: NextRequest) {
  const headers = new Headers(request.headers)
  // Never pass on a value the caller made up
  headers.delete("x-vb-proxy")
  const secret = process.env.SYNC_PROXY_SECRET
  if (secret) headers.set("x-vb-proxy", secret)
  return NextResponse.next({ request: { headers } })
}

export const config = {
  matcher: "/api/sync/:path*",
}
