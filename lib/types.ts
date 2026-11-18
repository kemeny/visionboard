export type FontStyle = 'clean' | 'editorial' | 'mono' | 'handwritten' | 'loud' | 'elegant' | 'compact' | 'poster'

export interface TextStyleConfig {
  id: FontStyle
  label: string
  fontFamily: string
  fontWeight: number
  fontStyle: 'normal' | 'italic'
  letterSpacing: string
  lineHeight: string
  textTransform: 'none' | 'uppercase' | 'lowercase'
  className: string // tailwind classes for preview
}

export const TEXT_STYLES: TextStyleConfig[] = [
  {
    id: 'clean', label: 'Clean',
    fontFamily: 'system-ui, -apple-system, sans-serif', fontWeight: 600, fontStyle: 'normal',
    letterSpacing: '-0.01em', lineHeight: '1.3', textTransform: 'none',
    className: 'font-semibold',
  },
  {
    id: 'editorial', label: 'Editorial',
    fontFamily: 'Georgia, "Times New Roman", serif', fontWeight: 400, fontStyle: 'italic',
    letterSpacing: '0em', lineHeight: '1.35', textTransform: 'none',
    className: 'font-serif italic',
  },
  {
    id: 'loud', label: 'Loud',
    fontFamily: 'system-ui, -apple-system, sans-serif', fontWeight: 900, fontStyle: 'normal',
    letterSpacing: '-0.03em', lineHeight: '1.1', textTransform: 'uppercase',
    className: 'font-black uppercase',
  },
  {
    id: 'elegant', label: 'Elegant',
    fontFamily: 'Georgia, "Times New Roman", serif', fontWeight: 400, fontStyle: 'normal',
    letterSpacing: '0.06em', lineHeight: '1.5', textTransform: 'uppercase',
    className: 'font-serif uppercase tracking-widest',
  },
  {
    id: 'mono', label: 'Mono',
    fontFamily: '"SF Mono", "Fira Code", "Courier New", monospace', fontWeight: 500, fontStyle: 'normal',
    letterSpacing: '0em', lineHeight: '1.5', textTransform: 'none',
    className: 'font-mono font-medium',
  },
  {
    id: 'handwritten', label: 'Script',
    fontFamily: '"Segoe Script", "Bradley Hand", cursive', fontWeight: 400, fontStyle: 'normal',
    letterSpacing: '0em', lineHeight: '1.4', textTransform: 'none',
    className: '',
  },
  {
    id: 'compact', label: 'Compact',
    fontFamily: 'system-ui, -apple-system, sans-serif', fontWeight: 500, fontStyle: 'normal',
    letterSpacing: '0.08em', lineHeight: '1.2', textTransform: 'uppercase',
    className: 'font-medium uppercase tracking-wider',
  },
  {
    id: 'poster', label: 'Poster',
    fontFamily: 'Impact, "Arial Black", sans-serif', fontWeight: 400, fontStyle: 'normal',
    letterSpacing: '0em', lineHeight: '1.05', textTransform: 'uppercase',
    className: 'uppercase',
  },
]

export interface BoardItem {
  id: string
  type: 'image' | 'text'
  x: number
  y: number
  width: number
  height: number
  content: string
  zIndex: number
  fontStyle?: FontStyle
  fontSize?: number
  color?: string
  bgColor?: string
  rotation?: number
  originalContent?: string // stores original image before bg removal
  locked?: boolean
  liked?: boolean // hearted in the feed; synced with the board
  achievedAt?: string // ISO 8601 time it was marked "I did it"; absent while still a goal
  credit?: ImageCredit // who took the photo, for stock photos that need attribution
}

// Attribution kept with a photo, e.g. Unsplash photos added by the iOS AI board.
// Same shape as ios/VisionBoard/Model/BoardItem.swift (BoardItem.Credit).
export interface ImageCredit {
  name: string // the photographer
  url?: string // their profile page
  source?: string // where the photo came from, e.g. "unsplash"
}

export const UNSPLASH_REFERRAL_URL = 'https://unsplash.com/?utm_source=visionboard&utm_medium=referral'

// Unsplash photos are hotlinked from their CDN, as Unsplash's API guidelines
// ask, and never copied into our own image storage
export function isUnsplashImage(content: string | undefined): boolean {
  return typeof content === 'string' && content.startsWith('https://images.unsplash.com/')
}

// A credit link comes from synced board JSON that anyone with the sync key
// can write, so only an https link to unsplash.com is ever made clickable
export function safeCreditUrl(url: string | undefined): string | undefined {
  if (!url) return undefined
  try {
    const parsed = new URL(url)
    if (parsed.protocol !== 'https:') return undefined
    const host = parsed.hostname.toLowerCase()
    return host === 'unsplash.com' || host.endsWith('.unsplash.com') ? parsed.toString() : undefined
  } catch {
    return undefined
  }
}

export interface BoardState {
  items: BoardItem[]
}

export const TEXT_COLORS = [
  '#1a1a1a',
  '#6b7280',
  '#ef4444',
  '#f97316',
  '#eab308',
  '#22c55e',
  '#3b82f6',
  '#8b5cf6',
  '#ec4899',
  '#ffffff',
] as const

export const FONT_SIZES = [14, 18, 24, 32, 48, 64] as const
