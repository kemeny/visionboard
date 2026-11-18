import type { BoardItem } from './types'

// The progress loop: a clipping marked "I did it" keeps its spot on the board
// with a small seal, and shows up less often in the feed and reminders.

export const isAchieved = (item: BoardItem) => !!item.achievedAt

// Feed rounds keep an achieved clipping about 3 times in 10
export const ACHIEVED_WEIGHT = 0.3

// Ids start with the creation time in milliseconds ("1712345678901-ab12cd34")
export function createdAtFromId(id: string): number | null {
  const ms = Number(id.split('-')[0])
  return Number.isFinite(ms) && ms > 1_000_000_000_000 ? ms : null
}

export function daysSinceCreated(item: BoardItem, now = Date.now()): number | null {
  const created = createdAtFromId(item.id)
  if (created === null) return null
  return Math.max(0, Math.floor((now - created) / 86_400_000))
}
