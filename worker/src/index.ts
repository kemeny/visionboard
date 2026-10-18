// Vision Board sync API. Reached through the Next.js app at /api/sync/*.
//
// Auth is a "sync key": a random secret generated in the browser. The Worker
// only ever stores its SHA-256, which doubles as the board id.

import { generateVapidKeys, sendPush, type PushSubscriptionJSON, type VapidKeys } from './webpush'

interface Env {
  DB: D1Database
  IMAGES: R2Bucket
  VAPID_SUBJECT: string
}

interface BoardItem {
  type: 'image' | 'text'
  content: string
}

const MAX_BOARD_BYTES = 2 * 1024 * 1024
const MAX_IMAGE_BYTES = 10 * 1024 * 1024
const MIN_KEY_LENGTH = 20
const PLACEHOLDER_TEXT = 'Click to style, triple-click to edit'

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })
const error = (message: string, status: number) => json({ error: message }, status)

async function sha256Hex(data: ArrayBuffer | Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function boardIdFrom(request: Request): Promise<string | null> {
  const auth = request.headers.get('Authorization') || ''
  const key = auth.startsWith('Bearer ') ? auth.slice(7).trim() : ''
  if (key.length < MIN_KEY_LENGTH) return null
  return sha256Hex(new TextEncoder().encode(key))
}

// VAPID keys are created on first use and kept in D1, so no secrets need setting up
async function getVapidKeys(env: Env): Promise<VapidKeys> {
  const row = await env.DB.prepare("SELECT value FROM meta WHERE key = 'vapid'").first<{ value: string }>()
  if (row) return JSON.parse(row.value)
  const keys = await generateVapidKeys()
  await env.DB.prepare("INSERT OR IGNORE INTO meta (key, value) VALUES ('vapid', ?)").bind(JSON.stringify(keys)).run()
  // Re-read in case a concurrent request won the insert
  const saved = await env.DB.prepare("SELECT value FROM meta WHERE key = 'vapid'").first<{ value: string }>()
  return JSON.parse(saved!.value)
}

// Pick today's reminder, rotating through the board so each day shows something different
export function pickReminder(items: BoardItem[], day: number) {
  const texts = items
    .filter((i) => i.type === 'text' && i.content.trim() && i.content !== PLACEHOLDER_TEXT)
    .map((i) => i.content.trim())
  const images = items.filter((i) => i.type === 'image' && i.content.startsWith('/')).map((i) => i.content)
  return {
    body: texts.length ? texts[day % texts.length] : 'Take a minute with your vision board today.',
    image: images.length ? images[day % images.length] : undefined,
  }
}

function localTime(timezone: string, now: Date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now)
  const get = (t: string) => parts.find((p) => p.type === t)!.value
  return { day: `${get('year')}-${get('month')}-${get('day')}`, hour: Number(get('hour')) }
}

async function sendReminder(env: Env, vapid: VapidKeys, row: SubscriptionRow, now: Date): Promise<number> {
  const board = await env.DB.prepare('SELECT data FROM boards WHERE id = ?').bind(row.board_id).first<{ data: string }>()
  const items: BoardItem[] = board ? JSON.parse(board.data).items || [] : []
  const { body, image } = pickReminder(items, Math.floor(now.getTime() / 86_400_000))
  const origin = row.app_origin || ''
  // Tapping the notification opens today's goal and photo full screen. iOS
  // never shows images inside web notifications, so this is where they appear.
  const card = new URLSearchParams({ text: body, ...(image && { image }) })
  const status = await sendPush(
    JSON.parse(row.subscription) as PushSubscriptionJSON,
    {
      title: 'Your vision board',
      body,
      image: image && origin ? origin + image : undefined,
      url: `${origin}/#today&${card}`,
    },
    vapid,
    env.VAPID_SUBJECT
  )
  if (status === 404 || status === 410) {
    await env.DB.prepare('DELETE FROM push_subscriptions WHERE endpoint = ?').bind(row.endpoint).run()
  }
  return status
}

interface SubscriptionRow {
  endpoint: string
  board_id: string
  subscription: string
  timezone: string
  local_hour: number
  last_sent_day: string | null
  app_origin: string | null
}

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url)
  // Accept both direct calls and calls proxied with the /api/sync prefix intact
  const path = url.pathname.replace(/^\/api\/sync/, '') || '/'
  const method = request.method

  if (path === '/health') return json({ ok: true })

  // Public image reads: ids are unguessable hashes
  const imageMatch = path.match(/^\/images\/([0-9a-f]{64})\/([0-9a-f]{64})$/)
  if (imageMatch && method === 'GET') {
    const obj = await env.IMAGES.get(`${imageMatch[1]}/${imageMatch[2]}`)
    if (!obj) return error('Not found', 404)
    return new Response(obj.body, {
      headers: {
        'Content-Type': obj.httpMetadata?.contentType || 'application/octet-stream',
        'Cache-Control': 'public, max-age=31536000, immutable',
        'Access-Control-Allow-Origin': '*',
      },
    })
  }

  if (path === '/push/public-key' && method === 'GET') {
    return json({ publicKey: (await getVapidKeys(env)).publicKey })
  }

  const boardId = await boardIdFrom(request)
  if (!boardId) return error('Missing or invalid sync key', 401)

  if (path === '/board' && method === 'GET') {
    const row = await env.DB.prepare('SELECT data, updated_at FROM boards WHERE id = ?')
      .bind(boardId)
      .first<{ data: string; updated_at: number }>()
    if (!row) return error('No board for this key', 404)
    return json({ board: JSON.parse(row.data), updatedAt: row.updated_at })
  }

  if (path === '/board' && method === 'PUT') {
    const text = await request.text()
    if (text.length > MAX_BOARD_BYTES) return error('Board too large; upload images separately', 413)
    let board: { items?: unknown }
    try {
      board = JSON.parse(text)
    } catch {
      return error('Invalid JSON', 400)
    }
    if (!Array.isArray(board.items)) return error('Board needs an items array', 400)
    const updatedAt = Date.now()
    await env.DB.prepare(
      'INSERT INTO boards (id, data, updated_at) VALUES (?1, ?2, ?3) ON CONFLICT(id) DO UPDATE SET data = ?2, updated_at = ?3'
    )
      .bind(boardId, text, updatedAt)
      .run()
    return json({ updatedAt })
  }

  if (path === '/board' && method === 'DELETE') {
    let cursor: string | undefined
    do {
      const list = await env.IMAGES.list({ prefix: `${boardId}/`, cursor })
      if (list.objects.length) await env.IMAGES.delete(list.objects.map((o) => o.key))
      cursor = list.truncated ? list.cursor : undefined
    } while (cursor)
    await env.DB.batch([
      env.DB.prepare('DELETE FROM boards WHERE id = ?').bind(boardId),
      env.DB.prepare('DELETE FROM push_subscriptions WHERE board_id = ?').bind(boardId),
    ])
    return json({ ok: true })
  }

  if (path === '/images' && method === 'PUT') {
    const contentType = request.headers.get('Content-Type') || ''
    if (!contentType.startsWith('image/')) return error('Only images are accepted', 415)
    const bytes = await request.arrayBuffer()
    if (bytes.byteLength > MAX_IMAGE_BYTES) return error('Image too large (10 MB max)', 413)
    const hash = await sha256Hex(bytes)
    const key = `${boardId}/${hash}`
    if (!(await env.IMAGES.head(key))) {
      await env.IMAGES.put(key, bytes, { httpMetadata: { contentType } })
    }
    return json({ path: `/api/sync/images/${key}` })
  }

  if (path === '/push/subscribe' && method === 'POST') {
    const body = await request.json<{ subscription?: PushSubscriptionJSON; timezone?: string; localHour?: number }>()
    const sub = body.subscription
    if (!sub?.endpoint?.startsWith('https://') || !sub.keys?.p256dh || !sub.keys?.auth) {
      return error('Invalid subscription', 400)
    }
    const hour = Number(body.localHour)
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) return error('localHour must be 0-23', 400)
    const timezone = body.timezone || 'UTC'
    try {
      localTime(timezone, new Date())
    } catch {
      return error('Unknown timezone', 400)
    }
    const origin = request.headers.get('Origin') || null
    await env.DB.prepare(
      `INSERT INTO push_subscriptions (endpoint, board_id, subscription, timezone, local_hour, created_at, app_origin)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT(endpoint) DO UPDATE SET board_id = ?2, subscription = ?3, timezone = ?4, local_hour = ?5, app_origin = ?7`
    )
      .bind(sub.endpoint, boardId, JSON.stringify(sub), timezone, hour, Date.now(), origin)
      .run()
    return json({ ok: true })
  }

  if (path === '/push/unsubscribe' && method === 'POST') {
    const { endpoint } = await request.json<{ endpoint?: string }>()
    await env.DB.prepare('DELETE FROM push_subscriptions WHERE endpoint = ? AND board_id = ?')
      .bind(endpoint || '', boardId)
      .run()
    return json({ ok: true })
  }

  if (path === '/push/test' && method === 'POST') {
    const { endpoint } = await request.json<{ endpoint?: string }>()
    const row = await env.DB.prepare('SELECT * FROM push_subscriptions WHERE endpoint = ? AND board_id = ?')
      .bind(endpoint || '', boardId)
      .first<SubscriptionRow>()
    if (!row) return error('Not subscribed', 404)
    const status = await sendReminder(env, await getVapidKeys(env), row, new Date())
    return json({ status }, status < 300 ? 200 : 502)
  }

  return error('Not found', 404)
}

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await handle(request, env)
    } catch (e) {
      console.error(e)
      return error('Server error', 500)
    }
  },

  async scheduled(_event, env, ctx): Promise<void> {
    const now = new Date()
    const { results } = await env.DB.prepare('SELECT * FROM push_subscriptions').all<SubscriptionRow>()
    const due = results.filter((row) => {
      try {
        const t = localTime(row.timezone, now)
        return t.hour === row.local_hour && row.last_sent_day !== t.day
      } catch {
        return false
      }
    })
    if (!due.length) return
    const vapid = await getVapidKeys(env)
    ctx.waitUntil(
      Promise.allSettled(
        due.map(async (row) => {
          const status = await sendReminder(env, vapid, row, now)
          if (status < 300) {
            await env.DB.prepare('UPDATE push_subscriptions SET last_sent_day = ? WHERE endpoint = ?')
              .bind(localTime(row.timezone, now).day, row.endpoint)
              .run()
          }
        })
      )
    )
  },
} satisfies ExportedHandler<Env>

