// Shows the daily vision board reminder sent by the sync Worker

// Where a tapped reminder is parked until the app picks it up (see lib/sync.ts)
const PENDING_CACHE = 'vb-pending'
const PENDING_KEY = '/__pending-card'

// Take over straight away instead of waiting for every open tab to close, so a
// fix here reaches an app that stays open in the background (as iOS apps do)
self.addEventListener('install', () => self.skipWaiting())
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()))

self.addEventListener('push', (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch {}
  event.waitUntil(
    self.registration.showNotification(data.title || 'Your vision board', {
      body: data.body || 'Take a minute with your vision board today.',
      icon: '/icon.png',
      badge: '/icon.png',
      image: data.image,
      tag: 'daily-reminder',
      data: { url: data.url || '/' },
    })
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  // Open on this app's own address, whatever address the reminder was saved under,
  // so an installed Home Screen app opens itself rather than a browser tab
  const url = self.location.origin + '/' + new URL(event.notification.data?.url || '/', self.location.origin).hash
  event.waitUntil(
    (async () => {
      // A suspended app can miss the message below, so also leave the card
      // where the app looks when it comes back to the foreground
      const cache = await caches.open(PENDING_CACHE)
      await cache.put(PENDING_KEY, new Response(JSON.stringify({ url, at: Date.now() })))

      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      const open = windows.find((w) => new URL(w.url).origin === self.location.origin)
      if (!open) return self.clients.openWindow(url)
      open.postMessage({ type: 'open-url', url })
      return open.focus()
    })()
  )
})
