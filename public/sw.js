// Shows the daily vision board reminder sent by the sync Worker
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
  const url = event.notification.data?.url || '/'
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      const open = windows.find((w) => new URL(w.url).origin === self.location.origin)
      if (!open) return self.clients.openWindow(url)
      // The app is already open: tell it to show the card, then bring it forward
      open.postMessage({ type: 'open-url', url })
      return open.focus()
    })
  )
})
