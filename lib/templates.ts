import { BoardItem } from './types'
import type { Lang } from './i18n'

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
    description: 'Start from scratch. Just you and the canvas.',
    emoji: '📋',
    items: [],
  },
]

// Spanish names, descriptions and clipping text for the templates above.
// Clipping text is keyed by the English text.
const TEMPLATE_ES: Record<string, { name: string; description: string }> = {
  'this-year': { name: 'Este año', description: 'Imagina cómo quieres que se vea y se sienta este año' },
  career: { name: 'Mi carrera', description: 'Diseña la vida laboral que de verdad quieres' },
  life: { name: 'Mi vida', description: 'La foto completa de quién te estás volviendo' },
  blank: { name: 'Tablero en blanco', description: 'Empieza desde cero. Solo tú y el lienzo.' },
}

const CONTENT_ES: Record<string, string> = {
  'This year I will...': 'Este año voy a...',
  'Places I want to go': 'Lugares a los que quiero ir',
  'How I want to feel': 'Cómo me quiero sentir',
  'Things to learn': 'Cosas por aprender',
  'People to connect with': 'Personas con quienes conectar',
  'Drop images of what inspires you anywhere on the board': 'Suelta en el tablero imágenes de lo que te inspira',
  'My career vision': 'Mi visión profesional',
  'The role I want': 'El rol que quiero',
  'Skills to build': 'Habilidades por crecer',
  'People who inspire me': 'Personas que me inspiran',
  'What success feels like': 'Cómo se siente el éxito',
  'Add images of your dream workspace, mentors, goals': 'Agrega imágenes de tu espacio ideal, tus mentores, tus metas',
  'The life I am building': 'La vida que estoy construyendo',
  'Home & space': 'Hogar y espacio',
  'Health & body': 'Salud y cuerpo',
  'Relationships': 'Relaciones',
  'Adventures': 'Aventuras',
  'Purpose & meaning': 'Propósito y sentido',
}

export function localizeTemplate(template: BoardTemplate, lang: Lang): BoardTemplate {
  if (lang !== 'es') return template
  const es = TEMPLATE_ES[template.id]
  return {
    ...template,
    name: es?.name ?? template.name,
    description: es?.description ?? template.description,
    items: template.items.map((item) =>
      item.type === 'text' && CONTENT_ES[item.content] ? { ...item, content: CONTENT_ES[item.content] } : item
    ),
  }
}
