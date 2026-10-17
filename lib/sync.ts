import { BoardItem } from './types'

// Proxied to the Cloudflare Worker by next.config.mjs
const API = '/api/sync'
const KEY_STORAGE = 'visionboard-sync-key'
const SYNCED_AT_STORAGE = 'visionboard-synced-at'
const REMINDER_STORAGE = 'visionboard-reminder'

export interface RemoteBoard {
  items: BoardItem[]
  maxZIndex: number
}

export class SyncError extends Error {
  constructor(message: string, public status: number) {
    super(message)
  }
}

// 20 random bytes as base32, grouped for easy copying: "k3fa-9qzt-..."
export function generateSyncKey(): string {
  const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789'
  const bytes = crypto.getRandomValues(new Uint8Array(20))
  const chars = Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('')
  return chars.match(/.{4}/g)!.join('-')
}

export function normalizeSyncKey(input: string): string {
  return input.trim().toLowerCase().replace(/\s+/g, '')
}

function read(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function write(key: string, value: string | null) {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {}
}

export const getSyncKey = () => read(KEY_STORAGE)
export const setSyncKey = (key: string | null) => write(KEY_STORAGE, key)
export const getSyncedAt = () => Number(read(SYNCED_AT_STORAGE) || 0)
export const setSyncedAt = (t: number) => write(SYNCED_AT_STORAGE, String(t))

async function api<T>(path: string, key: string | null, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  if (key) headers.set('Authorization', `Bearer ${key}`)
  const res = await fetch(API + path, { ...init, headers })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new SyncError(body.error || `Request failed (${res.status})`, res.status)
  return body as T
}

export async function isSyncAvailable(): Promise<boolean> {
  try {
    await api('/health', null)
    return true
  } catch {
    return false
  }
}

export async function fetchRemoteBoard(key: string): Promise<{ board: RemoteBoard; updatedAt: number } | null> {
  try {
    return await api('/board', key)
  } catch (e) {
    if (e instanceof SyncError && e.status === 404) return null
    throw e
  }
}

export async function pushRemoteBoard(key: string, board: RemoteBoard): Promise<number> {
  const { updatedAt } = await api<{ updatedAt: number }>('/board', key, {
    method: 'PUT',
    body: JSON.stringify(board),
  })
  return updatedAt
}

export async function deleteRemoteBoard(key: string): Promise<void> {
  await api('/board', key, { method: 'DELETE' })
}

const isDataUrl = (s?: string) => !!s && s.startsWith('data:')

async function uploadDataUrl(key: string, dataUrl: string): Promise<string> {
  const blob = await (await fetch(dataUrl)).blob()
  const { path } = await api<{ path: string }>('/images', key, {
    method: 'PUT',
    headers: { 'Content-Type': blob.type || 'image/png' },
    body: blob,
  })
  return path
}

// Upload any inline images and return a map of data URL -> hosted path
export async function uploadInlineImages(key: string, items: BoardItem[]): Promise<Map<string, string>> {
  const pending = new Set<string>()
  for (const item of items) {
    if (item.type !== 'image') continue
    if (isDataUrl(item.content)) pending.add(item.content)
    if (isDataUrl(item.originalContent)) pending.add(item.originalContent!)
  }
  const uploaded = new Map<string, string>()
  for (const dataUrl of pending) {
    uploaded.set(dataUrl, await uploadDataUrl(key, dataUrl))
  }
  return uploaded
}

export function replaceImageUrls(items: BoardItem[], uploaded: Map<string, string>): BoardItem[] {
  if (!uploaded.size) return items
  return items.map((item) => {
    const content = uploaded.get(item.content)
    const original = item.originalContent ? uploaded.get(item.originalContent) : undefined
    if (!content && !original) return item
    return { ...item, ...(content && { content }), ...(original && { originalContent: original }) }
  })
}

export const hasInlineImages = (items: BoardItem[]) =>
  items.some((i) => isDataUrl(i.content) || isDataUrl(i.originalContent))

// --- Daily reminders (Web Push) ---

export interface ReminderPref {
  hour: number
}

export const getReminderPref = (): ReminderPref | null => {
  const raw = read(REMINDER_STORAGE)
  try {
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

export function pushSupported(): boolean {
  return typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window
}

export function isIos(): boolean {
  return typeof navigator !== 'undefined' && /iPad|iPhone|iPod/.test(navigator.userAgent)
}

function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padded = (base64 + '='.repeat((4 - (base64.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(padded)
  return Uint8Array.from(raw, (c) => c.charCodeAt(0))
}

async function getSubscription(create: boolean): Promise<PushSubscription | null> {
  const reg = await navigator.serviceWorker.register('/sw.js')
  await navigator.serviceWorker.ready
  const existing = await reg.pushManager.getSubscription()
  if (existing || !create) return existing
  const { publicKey } = await api<{ publicKey: string }>('/push/public-key', null)
  return reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(publicKey) as BufferSource,
  })
}

export async function enableReminders(key: string, hour: number): Promise<void> {
  const permission = await Notification.requestPermission()
  if (permission !== 'granted') throw new SyncError('Notifications are blocked for this site in your browser settings', 403)
  const subscription = await getSubscription(true)
  await api('/push/subscribe', key, {
    method: 'POST',
    body: JSON.stringify({
      subscription: subscription!.toJSON(),
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      localHour: hour,
    }),
  })
  write(REMINDER_STORAGE, JSON.stringify({ hour }))
}

export async function disableReminders(key: string | null): Promise<void> {
  write(REMINDER_STORAGE, null)
  if (!pushSupported()) return
  const subscription = await getSubscription(false).catch(() => null)
  if (!subscription) return
  if (key) {
    await api('/push/unsubscribe', key, {
      method: 'POST',
      body: JSON.stringify({ endpoint: subscription.endpoint }),
    }).catch(() => {})
  }
  await subscription.unsubscribe()
}

export async function sendTestReminder(key: string): Promise<void> {
  const subscription = await getSubscription(false)
  if (!subscription) throw new SyncError('Reminders are not set up on this device', 400)
  await api('/push/test', key, { method: 'POST', body: JSON.stringify({ endpoint: subscription.endpoint }) })
}
