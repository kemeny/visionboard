import type { BoardItem } from './types'
import { ACHIEVED_WEIGHT, isAchieved } from './progress'

// Ranking for the feed: an Instagram-style "for you" order over the board's
// clippings. Likes live on the items (so they sync); views and dwell time are
// per-device engagement signals kept in localStorage.

export interface ItemStats {
  views: number
  dwellMs: number
  lastSeen: number
}

export type FeedStats = Record<string, ItemStats>

const STATS_KEY = 'visionboard-feed-stats'
const HOUR = 60 * 60 * 1000
// New text clippings start with this hint, in the language the board was made in
const PLACEHOLDER_TEXTS = new Set(['Click to style, triple-click to edit', 'Toca para dar estilo, triple toque para editar'])

export function loadFeedStats(): FeedStats {
  try {
    return JSON.parse(localStorage.getItem(STATS_KEY) || '{}')
  } catch {
    return {}
  }
}

export function saveFeedStats(stats: FeedStats): void {
  try {
    localStorage.setItem(STATS_KEY, JSON.stringify(stats))
  } catch {}
}

export function recordView(stats: FeedStats, id: string, dwellMs: number, now = Date.now()): FeedStats {
  const prev = stats[id] || { views: 0, dwellMs: 0, lastSeen: 0 }
  return { ...stats, [id]: { views: prev.views + 1, dwellMs: prev.dwellMs + dwellMs, lastSeen: now } }
}

export const isFeedItem = (i: BoardItem) =>
  i.type === 'image' ? !!i.content : !!i.content.trim() && !PLACEHOLDER_TEXTS.has(i.content.trim())

// Higher is shown sooner. Weights are deliberately gentle so the jitter keeps
// every load a little different, and nothing is ever buried for good.
export function scoreItem(item: BoardItem, stats: ItemStats | undefined, now: number, random: () => number): number {
  let score = 1
  if (item.liked) score += 0.9
  if (stats) {
    // Lingering on something is a quiet "like"; cap it so one long stare doesn't dominate
    const avgDwellSec = stats.dwellMs / Math.max(1, stats.views) / 1000
    score += 0.4 * Math.min(avgDwellSec / 6, 1)
    // Freshness: the longer since you last saw it, the more it rises again
    score += 0.6 * Math.min((now - stats.lastSeen) / (24 * HOUR), 1)
  } else {
    score += 0.8 // never seen on this device
  }
  return score + random() * 0.9
}

// One pass over every clipping, ranked, then spread out so the feed alternates
// between photos and words. `avoid` holds ids shown just before this round so
// the seam between rounds doesn't repeat.
export function buildFeedRound(
  items: BoardItem[],
  stats: FeedStats,
  options: { now?: number; random?: () => number; avoid?: string[]; likedOnly?: boolean } = {}
): BoardItem[] {
  const now = options.now ?? Date.now()
  const random = options.random ?? Math.random
  const eligible = items.filter(isFeedItem).filter((i) => !options.likedOnly || i.liked)
  // Done goals still come back, just less often. Liked keeps everything liked,
  // and a board where everything is done still has a feed.
  const thin = !options.likedOnly && eligible.some((i) => !isAchieved(i))
  const pool = thin ? eligible.filter((i) => !isAchieved(i) || random() < ACHIEVED_WEIGHT) : eligible
  const ranked = pool
    .map((item) => ({ item, score: scoreItem(item, stats[item.id], now, random) }))
    .sort((a, b) => b.score - a.score)
    .map((r) => r.item)

  // Push the last few from the previous round to the back half
  const avoid = new Set(options.avoid || [])
  const fresh = ranked.filter((i) => !avoid.has(i.id))
  const recent = ranked.filter((i) => avoid.has(i.id))
  const ordered = [...fresh.slice(0, Math.ceil(fresh.length / 2)), ...recent, ...fresh.slice(Math.ceil(fresh.length / 2))]

  // Never more than two text cards in a row when a photo is available to break them up
  const out: BoardItem[] = []
  const queue = [...ordered]
  while (queue.length) {
    const lastTwoText = out.length >= 2 && out[out.length - 1].type === 'text' && out[out.length - 2].type === 'text'
    const idx = lastTwoText ? queue.findIndex((i) => i.type === 'image') : 0
    out.push(queue.splice(idx === -1 ? 0 : idx, 1)[0])
  }
  return out
}
