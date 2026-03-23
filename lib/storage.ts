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
