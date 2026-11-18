'use client'

import posthog from 'posthog-js'

// Product analytics and feature flags (PostHog). Anonymous: no person
// profiles unless someone is identified, no autocapture, no session
// recording, and Do Not Track is respected. Never put board content (goal
// text, photos, board names) in properties; counts and enums only.

const DEFAULT_KEY = 'phc_mrhZ2PzAFJPf57JVGdswQsyujx8qEWgfxWbDDKXYsmxC'
// The production key is the fallback only for production deploys, so local
// dev and Vercel previews don't send events to the launch project.
const IS_PROD_DEPLOY = process.env.NODE_ENV === 'production' && process.env.NEXT_PUBLIC_VERCEL_ENV !== 'preview'
const KEY = process.env.NEXT_PUBLIC_POSTHOG_KEY || (IS_PROD_DEPLOY ? DEFAULT_KEY : '')

// URL fragments carry the sync key (#sync=...) and reminder content
// (#today&text=...). They must never reach analytics.
function stripHash(url: unknown): unknown {
  if (typeof url !== 'string') return url
  const i = url.indexOf('#')
  return i === -1 ? url : url.slice(0, i)
}

const URL_PROPS = ['$current_url', '$referrer', '$initial_current_url', '$session_entry_url', '$initial_referrer']

let started = false

export function initAnalytics(): void {
  if (started || typeof window === 'undefined' || !KEY) return
  started = true
  posthog.init(KEY, {
    // Proxied through next.config.mjs so ad blockers don't drop events
    api_host: '/ingest',
    ui_host: 'https://us.posthog.com',
    person_profiles: 'identified_only',
    capture_pageview: true,
    capture_pageleave: true,
    autocapture: false,
    disable_session_recording: true,
    respect_dnt: true,
    disable_capture_url_hashes: true,
    before_send: (event) => {
      if (!event) return event
      const props = event.properties as Record<string, unknown> | undefined
      if (props) {
        for (const key of URL_PROPS) {
          if (key in props) props[key] = stripHash(props[key])
        }
        for (const key of URL_PROPS) {
          const v = props[key]
          if (typeof v === 'string' && (v.includes('sync=') || v.includes('#today'))) return null
        }
      }
      return event
    },
    loaded: (ph) => {
      ph.register({ product: 'visionboard', platform: 'web' })
    },
  })
}

export function track(event: string, props?: Record<string, unknown>): void {
  initAnalytics()
  if (!started) return
  try {
    posthog.capture(event, props)
  } catch {
    // Analytics must never break the board
  }
}

export function getFlag(key: string): string | boolean | undefined {
  initAnalytics()
  if (!started) return undefined
  return posthog.getFeatureFlag(key)
}

// Calls back once flags are loaded, and again whenever they change.
// Returns a function that stops listening.
export function onFlags(cb: (flags: string[], variants: Record<string, string | boolean>) => void): () => void {
  initAnalytics()
  if (!started) return () => {}
  return posthog.onFeatureFlags((flags, variants) => cb(flags, variants))
}
