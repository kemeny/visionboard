'use client'

import { useEffect } from 'react'
import { initAnalytics } from '@/lib/analytics'

// Starts PostHog once in the browser. Renders nothing.
export function AnalyticsProvider() {
  useEffect(() => {
    initAnalytics()
  }, [])
  return null
}
