'use client'

import posthog from 'posthog-js'

// Product analytics and feature flags (PostHog). Anonymous: no person
// profiles unless someone is identified, no autocapture, no session
// recording, and Do Not Track is respected. Never put board content (goal
// text, photos, board names) in properties; counts and enums only.

const DEFAULT_KEY = 'phc_mrhZ2PzAFJPf57JVGdswQsyujx8qEWgfxWbDDKXYsmxC'
const KEY = process.env.NEXT_PUBLIC_POSTHOG_KEY || DEFAULT_KEY

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
