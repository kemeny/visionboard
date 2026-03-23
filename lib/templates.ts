import { BoardItem } from './types'

export interface BoardTemplate {
  id: string
  name: string
  description: string
  emoji: string
  items: Omit<BoardItem, 'id'>[]
}

function t(
  content: string,
  x: number,
  y: number,
  opts: Partial<BoardItem> = {}
): Omit<BoardItem, 'id'> {
  return {
    type: 'text',
    x,
    y,
    width: opts.width || 220,
    height: opts.height || 100,
    content,
    zIndex: opts.zIndex || 1,
    fontStyle: opts.fontStyle || 'clean',
    fontSize: opts.fontSize || 18,
    color: opts.color || '#1a1a1a',
    bgColor: opts.bgColor || 'transparent',
    rotation: opts.rotation || 0,
  }
}

export const TEMPLATES: BoardTemplate[] = [
  {
    id: 'this-year',
    name: 'This Year',
    description: 'Map out what you want this year to look and feel like',
    emoji: '✨',
    items: [
      t('This year I will...', 120, 80, {
        fontStyle: 'loud',
        fontSize: 48,
        width: 500,
        height: 80,
        zIndex: 10,
      }),
      t('Places I want to go', 120, 200, {
        fontStyle: 'editorial',
        fontSize: 24,
        width: 280,
        height: 60,
        bgColor: 'rgba(59,130,246,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('How I want to feel', 440, 200, {
        fontStyle: 'elegant',
        fontSize: 24,
        width: 280,
        height: 60,
        bgColor: 'rgba(236,72,153,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('Things to learn', 120, 420, {
        fontStyle: 'mono',
        fontSize: 24,
        width: 280,
        height: 60,
        bgColor: 'rgba(139,92,246,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('People to connect with', 440, 420, {
        fontStyle: 'compact',
        fontSize: 24,
        width: 280,
        height: 60,
        bgColor: 'rgba(34,197,94,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('Drop images of what inspires you anywhere on the board', 200, 620, {
        fontStyle: 'handwritten',
        fontSize: 16,
        width: 360,
        height: 50,
        color: '#6b7280',
        zIndex: 2,
      }),
    ],
  },
  {
    id: 'career',
    name: 'Career Vision',
    description: 'Design the work life you actually want',
    emoji: '🚀',
    items: [
      t('My career vision', 120, 80, {
        fontStyle: 'loud',
        fontSize: 48,
        width: 460,
        height: 80,
        zIndex: 10,
      }),
      t('The role I want', 120, 200, {
        fontStyle: 'editorial',
        fontSize: 24,
        width: 260,
        height: 60,
        bgColor: 'rgba(0,0,0,0.75)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('Skills to build', 420, 200, {
        fontStyle: 'mono',
        fontSize: 24,
        width: 260,
        height: 60,
        bgColor: 'rgba(59,130,246,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('People who inspire me', 120, 400, {
        fontStyle: 'compact',
        fontSize: 24,
        width: 260,
        height: 60,
        bgColor: 'rgba(139,92,246,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('What success feels like', 420, 400, {
        fontStyle: 'elegant',
        fontSize: 24,
        width: 260,
        height: 60,
        bgColor: 'rgba(234,179,8,0.85)',
        color: '#1a1a1a',
        zIndex: 5,
      }),
      t('Add images of your dream workspace, mentors, goals', 180, 580, {
        fontStyle: 'handwritten',
        fontSize: 16,
        width: 380,
        height: 50,
        color: '#6b7280',
        zIndex: 2,
      }),
    ],
  },
  {
    id: 'life',
    name: 'Life Vision',
    description: 'The big picture of who you are becoming',
    emoji: '🌿',
    items: [
      t('The life I am building', 120, 80, {
        fontStyle: 'loud',
        fontSize: 44,
        width: 520,
        height: 80,
        zIndex: 10,
      }),
      t('Home & space', 120, 200, {
        fontStyle: 'editorial',
        fontSize: 24,
        width: 240,
        height: 60,
        bgColor: 'rgba(234,179,8,0.85)',
        color: '#1a1a1a',
        zIndex: 5,
      }),
      t('Health & body', 400, 200, {
        fontStyle: 'clean',
        fontSize: 24,
        width: 240,
        height: 60,
        bgColor: 'rgba(34,197,94,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('Relationships', 120, 400, {
        fontStyle: 'elegant',
        fontSize: 24,
        width: 240,
        height: 60,
        bgColor: 'rgba(236,72,153,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('Adventures', 400, 400, {
        fontStyle: 'poster',
        fontSize: 24,
        width: 240,
        height: 60,
        bgColor: 'rgba(59,130,246,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
      t('Purpose & meaning', 240, 560, {
        fontStyle: 'handwritten',
        fontSize: 24,
        width: 280,
        height: 60,
        bgColor: 'rgba(139,92,246,0.85)',
        color: '#ffffff',
        zIndex: 5,
      }),
    ],
  },
  {
    id: 'blank',
    name: 'Blank Board',
    description: 'Start from scratch — just you and the canvas',
    emoji: '📋',
    items: [],
  },
]
