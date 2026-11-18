// Vision Board sync API. Reached through the Next.js app at /api/sync/*.
//
// Auth is a "sync key": a random secret generated in the browser. The Worker
// only ever stores its SHA-256, which doubles as the board id.

import { handleAI, overLimit, pruneRateLimits, type AIEnv } from './ai'
import { generateVapidKeys, sendPush, type PushSubscriptionJSON, type VapidKeys } from './webpush'
import {
  DEFAULT_BUNDLE_ID,
  TokenError,
  cleanBackup,
  decryptAppleToken,
  decryptBackup,
  encryptAppleToken,
  encryptBackup,
  exchangeAppleCode,
  revokeAppleToken,
  signSession,
  type AppleClientConfig,
  verifyAppleToken,
  verifySession,
} from './account'

interface Env extends AIEnv {
  DB: D1Database
  IMAGES: R2Bucket
  VAPID_SUBJECT: string
  // Secret (wrangler secret put ACCOUNT_SECRET): signs sessions and derives backup keys
  ACCOUNT_SECRET?: string
  // The iOS app's bundle id, the audience of its Apple identity tokens
  APPLE_BUNDLE_ID?: string
  // Secrets for the Sign in with Apple REST API (token revocation on delete)
  APPLE_TEAM_ID?: string
  APPLE_KEY_ID?: string
  APPLE_PRIVATE_KEY?: string
}

// Sign-ins per address per hour
const SIGNIN_LIMIT_PER_IP = 30

function appleClient(env: Env): AppleClientConfig | null {
  if (!env.APPLE_TEAM_ID || !env.APPLE_KEY_ID || !env.APPLE_PRIVATE_KEY) return null
  return {
    teamId: env.APPLE_TEAM_ID,
    keyId: env.APPLE_KEY_ID,
    privateKey: env.APPLE_PRIVATE_KEY,
    clientId: env.APPLE_BUNDLE_ID || DEFAULT_BUNDLE_ID,
  }
}

interface BoardItem {
  type: 'image' | 'text'
  content: string
  achievedAt?: string
  credit?: { name?: unknown; source?: unknown }
}

// Create with AI photos are hotlinked from Unsplash's CDN, never stored in R2
const UNSPLASH_IMAGE_PREFIX = 'https://images.unsplash.com/'
const isReminderImage = (content: string) =>
  content.startsWith('/') || content.startsWith(UNSPLASH_IMAGE_PREFIX)

const MAX_BOARD_BYTES = 2 * 1024 * 1024
const MAX_IMAGE_BYTES = 10 * 1024 * 1024
const MIN_KEY_LENGTH = 20
// Kept in step with lib/feed.ts: the hint a new text clipping starts with, in English and Spanish
const PLACEHOLDER_TEXTS = new Set(['Click to style, triple-click to edit', 'Toca para dar estilo, triple toque para editar'])

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
// Goals marked done ("I did it") step aside: today's goal is one still to do,
// unless every goal is done. Done photos come round 3 times in 10. The iOS app
// (DailyCard.pick) uses the same rotation, so phone and web agree.
export function pickReminder(items: BoardItem[], day: number) {
  const allTexts = items.filter((i) => i.type === 'text' && i.content.trim() && !PLACEHOLDER_TEXTS.has(i.content.trim()))
  const openTexts = allTexts.filter((i) => !i.achievedAt)
  const texts = (openTexts.length ? openTexts : allTexts).map((i) => i.content.trim())
  const imageItems = items.filter((i) => i.type === 'image' && typeof i.content === 'string' && isReminderImage(i.content))
  const images = imageItems.some((i) => i.achievedAt)
    ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].flatMap((round) =>
        imageItems.filter((i) => !i.achievedAt || (round % 3 === 0 && round < 9))
      )
    : imageItems
  const picked = images.length ? images[day % images.length] : undefined
  // Unsplash photos are shown with their photographer's name
  const name = picked?.credit?.name
  const credit =
    picked && picked.content.startsWith(UNSPLASH_IMAGE_PREFIX) && typeof name === 'string' && name.trim()
      ? name.trim().slice(0, 100)
      : undefined
  return {
    body: texts.length ? texts[day % texts.length] : 'Take a minute with your vision board today.',
    image: picked?.content,
    credit,
  }
}

// The subscriber's own calendar day as a day count, so the goal turns over at
// their midnight like on iOS, not at midnight UTC. Same number as the UTC day
// index on a UTC clock.
export function localDayNumber(timezone: string, now: Date): number {
  return Math.floor(Date.parse(`${localTime(timezone, now).day}T00:00:00Z`) / 86_400_000)
}

export function localTime(timezone: string, now: Date) {
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
  let day: number
  try {
    day = localDayNumber(row.timezone, now)
  } catch {
    day = Math.floor(now.getTime() / 86_400_000)
  }
  const { body, image, credit } = pickReminder(items, day)
  const origin = row.app_origin || ''
  // Tapping the notification opens today's goal and photo full screen. iOS
  // never shows images inside web notifications, so this is where they appear.
  const card = new URLSearchParams({ text: body, ...(image && { image }), ...(credit && { credit }) })
  const absoluteImage = image ? (image.startsWith('https://') ? image : origin ? origin + image : undefined) : undefined
  const status = await sendPush(
    JSON.parse(row.subscription) as PushSubscriptionJSON,
    {
      title: 'Your vision board',
      body,
      image: absoluteImage,
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

  if (path === '/account' || path.startsWith('/account/')) return handleAccount(path, method, request, env)

  // AI board generation needs no sync key (see ai.ts)
  const ai = await handleAI(request, env, path)
  if (ai) return ai

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

// Optional Sign in with Apple account: backs up the list of boards (name and
// sync key) so a new device can reconnect them. Auth is a session token.
async function handleAccount(path: string, method: string, request: Request, env: Env): Promise<Response> {
  const secret = env.ACCOUNT_SECRET
  if (!secret || secret.length < 32) return error('Accounts are not set up on this server', 503)

  if (path === '/account/signin' && method === 'POST') {
    if (await overLimit(env, request, 'signin', SIGNIN_LIMIT_PER_IP)) return error('Too many sign-ins. Try again later.', 429)
    let body: { identityToken?: unknown; nonce?: unknown; authorizationCode?: unknown }
    try {
      body = await request.json()
    } catch {
      return error('Invalid JSON', 400)
    }
    if (typeof body.identityToken !== 'string' || !body.identityToken) return error('identityToken is required', 400)
    if (typeof body.nonce !== 'string' || !body.nonce) return error('nonce is required', 400)
    let identity
    try {
      identity = await verifyAppleToken(body.identityToken, env.APPLE_BUNDLE_ID || DEFAULT_BUNDLE_ID, body.nonce)
    } catch (e) {
      if (e instanceof TokenError) return error(`Sign in failed: ${e.message}`, 401)
      throw e
    }
    // Apple's refresh token, so deleting the account can revoke it. Every
    // account must hold one: a failed exchange only falls back to the token
    // an existing account already has, and a new account isn't created
    // without it (the app shows the error and the person can try again).
    const client = appleClient(env)
    if (!client) return error('Sign in with Apple is not set up on this server', 503)
    let refreshCiphertext: string | null = null
    if (typeof body.authorizationCode === 'string' && body.authorizationCode) {
      const refreshToken = await exchangeAppleCode(body.authorizationCode, client).catch((e) => {
        console.error('apple token exchange failed', e)
        return null
      })
      if (refreshToken) refreshCiphertext = await encryptAppleToken(refreshToken, secret, identity.sub)
    }
    if (!refreshCiphertext) {
      const existing = await env.DB.prepare('SELECT apple_refresh_ciphertext FROM accounts WHERE id = ?')
        .bind(identity.sub)
        .first<{ apple_refresh_ciphertext: string | null }>()
      if (!existing?.apple_refresh_ciphertext) return error('Sign in with Apple could not be completed. Please try again.', 502)
    }
    const now = Date.now()
    // Apple only sends the email when it was shared, so keep the one we have
    await env.DB.prepare(
      `INSERT INTO accounts (id, email, created_at, updated_at, apple_refresh_ciphertext) VALUES (?1, ?2, ?3, ?3, ?4)
       ON CONFLICT(id) DO UPDATE SET email = COALESCE(?2, email), updated_at = ?3,
         apple_refresh_ciphertext = COALESCE(?4, apple_refresh_ciphertext)`
    )
      .bind(identity.sub, identity.email, now, refreshCiphertext)
      .run()
    const row = await env.DB.prepare('SELECT email, boards_ciphertext, created_at FROM accounts WHERE id = ?')
      .bind(identity.sub)
      .first<{ email: string | null; boards_ciphertext: string | null; created_at: number }>()
    if (!row) return error('Server error', 500)
    return json({
      sessionToken: await signSession(identity.sub, row.created_at, secret),
      email: row.email ?? null,
      hasBackup: Boolean(row.boards_ciphertext),
    })
  }

  const auth = request.headers.get('Authorization') || ''
  const session = auth.startsWith('Bearer ') ? await verifySession(auth.slice(7).trim(), secret) : null
  if (!session) return error('Please sign in again', 401)
  const accountId = session.sub

  const account = await env.DB.prepare(
    'SELECT email, boards_ciphertext, updated_at, created_at, apple_refresh_ciphertext FROM accounts WHERE id = ?'
  )
    .bind(accountId)
    .first<{
      email: string | null
      boards_ciphertext: string | null
      updated_at: number
      created_at: number
      apple_refresh_ciphertext: string | null
    }>()
  // A token from before the account was deleted and made again is void
  if (!account || account.created_at !== session.ep) return error('Please sign in again', 401)

  if (path === '/account/backup' && method === 'GET') {
    let boards: Awaited<ReturnType<typeof decryptBackup>> = []
    if (account.boards_ciphertext) {
      try {
        boards = await decryptBackup(account.boards_ciphertext, secret, accountId)
      } catch (e) {
        // ACCOUNT_SECRET changed: the app uploads a fresh backup
        console.error('backup unreadable', e)
        return error('backup_unreadable', 409)
      }
    }
    return json({ boards, email: account.email, updatedAt: account.updated_at })
  }

  if (path === '/account/backup' && method === 'PUT') {
    let body: { boards?: unknown }
    try {
      body = await request.json()
    } catch {
      return error('Invalid JSON', 400)
    }
    const boards = cleanBackup(body.boards)
    if (!boards) return error('boards must be a list of {name, syncKey}', 400)
    const updatedAt = Date.now()
    await env.DB.prepare('UPDATE accounts SET boards_ciphertext = ?1, updated_at = ?2 WHERE id = ?3')
      .bind(await encryptBackup(boards, secret, accountId), updatedAt, accountId)
      .run()
    return json({ ok: true, updatedAt })
  }

  if (path === '/account' && method === 'DELETE') {
    // Revoke the app's Apple tokens first (guideline 5.1.1(v)). If Apple
    // can't be reached the account stays, so the person can try again.
    const client = appleClient(env)
    if (client && account.apple_refresh_ciphertext) {
      let refreshToken: string | null = null
      try {
        refreshToken = await decryptAppleToken(account.apple_refresh_ciphertext, secret, accountId)
      } catch (e) {
        console.error('apple token unreadable', e)
      }
      if (refreshToken && !(await revokeAppleToken(refreshToken, client))) {
        return error("Couldn't reach Apple to finish deleting your account. Try again in a moment.", 502)
      }
    }
    // Boards stay under their sync keys; the app deletes those itself when asked to
    await env.DB.prepare('DELETE FROM accounts WHERE id = ?').bind(accountId).run()
    return json({ ok: true })
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
    ctx.waitUntil(pruneRateLimits(env, now.getTime()).catch((e) => console.error('prune ai_rate', e)))
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

