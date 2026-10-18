import { BoardItem } from './types'

const DB_NAME = 'visionboard'
const DB_VERSION = 1
const ITEMS_STORE = 'items'
const META_STORE = 'meta'

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION)
    request.onerror = () => reject(request.error)
    request.onsuccess = () => resolve(request.result)
    request.onupgradeneeded = () => {
      const db = request.result
      if (!db.objectStoreNames.contains(ITEMS_STORE)) {
        db.createObjectStore(ITEMS_STORE, { keyPath: 'id' })
      }
      if (!db.objectStoreNames.contains(META_STORE)) {
        db.createObjectStore(META_STORE)
      }
    }
  })
}

export async function saveItemsDB(items: BoardItem[]): Promise<void> {
  const db = await openDB()
  const tx = db.transaction(ITEMS_STORE, 'readwrite')
  const store = tx.objectStore(ITEMS_STORE)
  store.clear()
  for (const item of items) {
    store.put(item)
  }
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
}

export async function loadItemsDB(): Promise<BoardItem[]> {
  const db = await openDB()
  const tx = db.transaction(ITEMS_STORE, 'readonly')
  const store = tx.objectStore(ITEMS_STORE)
  const request = store.getAll()
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result || [])
    request.onerror = () => reject(request.error)
  })
}

export async function saveMaxZDB(z: number): Promise<void> {
  const db = await openDB()
  const tx = db.transaction(META_STORE, 'readwrite')
  const store = tx.objectStore(META_STORE)
  store.put(z, 'maxZIndex')
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
}

export async function loadMaxZDB(): Promise<number> {
  const db = await openDB()
  const tx = db.transaction(META_STORE, 'readonly')
  const store = tx.objectStore(META_STORE)
  const request = store.get('maxZIndex')
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result ?? 1)
    request.onerror = () => reject(request.error)
  })
}

// Ask the browser not to evict our data under storage pressure.
// Browsers may grant silently, prompt, or refuse; failure is harmless.
export async function requestPersistentStorage(): Promise<boolean> {
  try {
    if (!navigator.storage?.persist) return false
    if (await navigator.storage.persisted()) return true
    return await navigator.storage.persist()
  } catch {
    return false
  }
}

const LAST_BACKUP_KEY = 'visionboard-last-backup'
const BACKUP_SNOOZE_KEY = 'visionboard-backup-snooze'
const DAY = 24 * 60 * 60 * 1000

export function markBackedUp(): void {
  try {
    localStorage.setItem(LAST_BACKUP_KEY, String(Date.now()))
    localStorage.removeItem(BACKUP_SNOOZE_KEY)
  } catch {}
}

export function snoozeBackupReminder(days = 3): void {
  try {
    localStorage.setItem(BACKUP_SNOOZE_KEY, String(Date.now() + days * DAY))
  } catch {}
}

// Remind when a non-trivial board has never been backed up, or not in a week
export function shouldRemindBackup(itemCount: number): boolean {
  if (itemCount < 3) return false
  try {
    const snoozeUntil = Number(localStorage.getItem(BACKUP_SNOOZE_KEY) || 0)
    if (Date.now() < snoozeUntil) return false
    const last = Number(localStorage.getItem(LAST_BACKUP_KEY) || 0)
    return Date.now() - last > 7 * DAY
  } catch {
    return false
  }
}

// Migrate from localStorage to IndexedDB (one-time)
export async function migrateFromLocalStorage(): Promise<{ items: BoardItem[]; maxZ: number } | null> {
  if (typeof window === 'undefined') return null
  const raw = localStorage.getItem('visionboard-items')
  if (!raw) return null
  try {
    const items: BoardItem[] = JSON.parse(raw)
    const maxZ = parseInt(localStorage.getItem('visionboard-maxz') || '1', 10)
    await saveItemsDB(items)
    await saveMaxZDB(maxZ)
    // Clean up localStorage
    localStorage.removeItem('visionboard-items')
    localStorage.removeItem('visionboard-maxz')
    return { items, maxZ }
  } catch {
    return null
  }
}
