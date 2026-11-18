// Draws board clippings into a 1080 x 1920 story image (PNG) on board paper,
// with a small "Made with VisionBoard" mark at the bottom. Canvas based, so
// it needs no extra package. Mirrors how components/board-item.tsx draws a
// clipping: photos fill and crop to their box with rounded corners, words sit
// centered with the clipping's font, color and background.

import { BoardItem, TEXT_STYLES } from './types'

export const STORY_WIDTH = 1080
export const STORY_HEIGHT = 1920
export const SHARE_URL = 'https://visionboard.kemenystudio.com/?ref=share'

const INK = '#1a1a1a'
const RADIUS = 12

function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image()
    // Remote photos must allow CORS or the canvas can't be exported; those
    // that don't simply fail to load and are drawn as a soft placeholder
    if (!src.startsWith('data:') && !src.startsWith('blob:')) img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = src
  })
}

function roundedRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  const radius = Math.min(r, w / 2, h / 2)
  ctx.beginPath()
  ctx.moveTo(x + radius, y)
  ctx.arcTo(x + w, y, x + w, y + h, radius)
  ctx.arcTo(x + w, y + h, x, y + h, radius)
  ctx.arcTo(x, y + h, x, y, radius)
  ctx.arcTo(x, y, x + w, y, radius)
  ctx.closePath()
}

function drawPhoto(ctx: CanvasRenderingContext2D, item: BoardItem, img: HTMLImageElement | null) {
  const { width: w, height: h } = item
  // Shadow like Tailwind's shadow-lg
  ctx.save()
  ctx.shadowColor = 'rgba(0, 0, 0, 0.18)'
  ctx.shadowBlur = 16
  ctx.shadowOffsetY = 6
  roundedRect(ctx, 0, 0, w, h, RADIUS)
  ctx.fillStyle = '#e7e2d9'
  ctx.fill()
  ctx.restore()

  if (!img) return
  ctx.save()
  roundedRect(ctx, 0, 0, w, h, RADIUS)
  ctx.clip()
  // object-fit: cover
  const scale = Math.max(w / img.naturalWidth, h / img.naturalHeight)
  const dw = img.naturalWidth * scale
  const dh = img.naturalHeight * scale
  ctx.drawImage(img, (w - dw) / 2, (h - dh) / 2, dw, dh)
  ctx.restore()
}

function wrapLines(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string[] {
  const lines: string[] = []
  for (const paragraph of text.split('\n')) {
    const words = paragraph.split(/\s+/).filter(Boolean)
    if (words.length === 0) {
      lines.push('')
      continue
    }
    let line = ''
    for (const word of words) {
      const next = line ? `${line} ${word}` : word
      if (line && ctx.measureText(next).width > maxWidth) {
        lines.push(line)
        line = word
      } else {
        line = next
      }
    }
    lines.push(line)
  }
  return lines
}

function drawText(ctx: CanvasRenderingContext2D, item: BoardItem) {
  const { width: w, height: h } = item
  const style = TEXT_STYLES.find((s) => s.id === item.fontStyle) ?? TEXT_STYLES[0]
  const bg = item.bgColor && item.bgColor !== 'transparent' ? item.bgColor : null
  if (bg) {
    roundedRect(ctx, 0, 0, w, h, RADIUS)
    ctx.fillStyle = bg
    ctx.fill()
  }

  const padding = 16
  const maxWidth = Math.max(10, w - padding * 2)
  const maxHeight = Math.max(10, h - padding * 2)
  let content = item.content
  if (style.textTransform === 'uppercase') content = content.toUpperCase()
  if (style.textTransform === 'lowercase') content = content.toLowerCase()

  // Start at the clipping's size and shrink until the words fit the box
  let size = item.fontSize || 18
  let lines: string[] = []
  let lineHeight = 0
  for (let i = 0; i < 12; i++) {
    ctx.font = `${style.fontStyle} ${style.fontWeight} ${size}px ${style.fontFamily}`
    const spacing = parseFloat(style.letterSpacing) || 0
    if ('letterSpacing' in ctx) {
      ;(ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = `${spacing * size}px`
    }
    lines = wrapLines(ctx, content, maxWidth)
    lineHeight = size * (parseFloat(style.lineHeight) || 1.3)
    const tooWide = lines.some((l) => ctx.measureText(l).width > maxWidth)
    if ((lines.length * lineHeight <= maxHeight && !tooWide) || size <= 8) break
    size *= 0.88
  }

  ctx.fillStyle = item.color || INK
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  const top = h / 2 - (lines.length * lineHeight) / 2 + lineHeight / 2
  lines.forEach((line, i) => ctx.fillText(line, w / 2, top + i * lineHeight))
}

function drawMark(ctx: CanvasRenderingContext2D) {
  ctx.save()
  ctx.textAlign = 'center'
  ctx.textBaseline = 'alphabetic'
  if ('letterSpacing' in ctx) {
    ;(ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = '0px'
  }
  ctx.fillStyle = 'rgba(0, 0, 0, 0.5)'
  ctx.font = '600 36px system-ui, -apple-system, "Segoe UI", sans-serif'
  ctx.fillText('Made with VisionBoard', STORY_WIDTH / 2, STORY_HEIGHT - 140)
  ctx.font = '400 30px system-ui, -apple-system, "Segoe UI", sans-serif'
  ctx.fillText('visionboard.kemenystudio.com', STORY_WIDTH / 2, STORY_HEIGHT - 96)
  ctx.restore()
}

// Fits `items` into the story frame and returns the PNG, or null when the
// browser can't make one (for example a remote photo without CORS)
export async function renderBoardStory(
  items: BoardItem[],
  paper: string,
  options: { mark: boolean } = { mark: true },
): Promise<Blob | null> {
  const canvas = document.createElement('canvas')
  canvas.width = STORY_WIDTH
  canvas.height = STORY_HEIGHT
  const ctx = canvas.getContext('2d')
  if (!ctx) return null

  ctx.fillStyle = paper
  ctx.fillRect(0, 0, STORY_WIDTH, STORY_HEIGHT)

  const sorted = [...items].sort((a, b) => a.zIndex - b.zIndex)
  if (sorted.length > 0) {
    const photos = new Map<string, HTMLImageElement | null>()
    await Promise.all(
      sorted
        .filter((i) => i.type === 'image' && !photos.has(i.content))
        .map(async (i) => {
          photos.set(i.content, null)
          photos.set(i.content, await loadImage(i.content))
        }),
    )

    const minX = Math.min(...sorted.map((i) => i.x))
    const minY = Math.min(...sorted.map((i) => i.y))
    const maxX = Math.max(...sorted.map((i) => i.x + i.width))
    const maxY = Math.max(...sorted.map((i) => i.y + i.height))
    const boundsW = Math.max(1, maxX - minX)
    const boundsH = Math.max(1, maxY - minY)

    const side = 80
    const top = 140
    const bottom = options.mark ? 280 : 140
    const areaW = STORY_WIDTH - side * 2
    const areaH = STORY_HEIGHT - top - bottom
    const scale = Math.min(areaW / boundsW, areaH / boundsH, 4)
    const offsetX = side + (areaW - boundsW * scale) / 2 - minX * scale
    const offsetY = top + (areaH - boundsH * scale) / 2 - minY * scale

    for (const item of sorted) {
      ctx.save()
      ctx.translate(offsetX, offsetY)
      ctx.scale(scale, scale)
      ctx.translate(item.x + item.width / 2, item.y + item.height / 2)
      ctx.rotate(((item.rotation || 0) * Math.PI) / 180)
      ctx.translate(-item.width / 2, -item.height / 2)
      if (item.type === 'image') drawPhoto(ctx, item, photos.get(item.content) ?? null)
      else drawText(ctx, item)
      ctx.restore()
    }
  }

  if (options.mark) drawMark(ctx)

  return new Promise((resolve) => {
    try {
      canvas.toBlob((blob) => resolve(blob), 'image/png')
    } catch {
      resolve(null)
    }
  })
}

// Shares the image with the system share sheet when the browser can share
// files, otherwise downloads it. Returns how it went out, or null when the
// person cancelled the share sheet.
export async function shareOrDownloadImage(blob: Blob, filename: string): Promise<'share' | 'download' | null> {
  const file = new File([blob], filename, { type: 'image/png' })
  if (typeof navigator !== 'undefined' && navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: 'VisionBoard', url: SHARE_URL })
      return 'share'
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') return null
      // NotAllowedError (the click "expired" while the image was drawn) and
      // others fall through to a download
    }
  }
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  return 'download'
}
