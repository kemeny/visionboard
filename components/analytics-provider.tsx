'use client'

import { useEffect } from 'react'
import { initAnalytics, track } from '@/lib/analytics'

const LAST_OPEN_KEY = 'vb-last-open'
// Coming back after this long counts as a new open, like the iOS app
const REOPEN_AFTER_MS = 30 * 60 * 1000

function startOfDay(t: number): number {
  const d = new Date(t)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

function trackOpen(): void {
  const now = Date.now()
  let last: number | null = null
  try {
    const raw = localStorage.getItem(LAST_OPEN_KEY)
    last = raw ? Number(raw) : null
    localStorage.setItem(LAST_OPEN_KEY, String(now))
  } catch {
    // Storage can be blocked; the open still counts
  }
  const props: Record<string, unknown> = { first_open: last === null }
  if (last !== null && Number.isFinite(last)) {
    // Calendar days, so 11 PM then 7 AM counts as a day later
    props.days_since_last_open = Math.max(0, Math.round((startOfDay(now) - startOfDay(last)) / 86_400_000))
  }
  track('app_opened', props)
}

// Starts PostHog once in the browser and records app_opened. Renders nothing.
export function AnalyticsProvider() {
  useEffect(() => {
    initAnalytics()
    trackOpen()
    let hiddenAt: number | null = null
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') {
        hiddenAt = Date.now()
      } else if (hiddenAt !== null && Date.now() - hiddenAt > REOPEN_AFTER_MS) {
        hiddenAt = null
        trackOpen()
      } else {
        hiddenAt = null
      }
    }
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [])
  return null
}
