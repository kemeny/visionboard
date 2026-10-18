"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { BoardItem } from "@/lib/types"
import {
  deleteRemoteBoard,
  disableReminders,
  fetchRemoteBoard,
  generateSyncKey,
  getSyncKey,
  getSyncedAt,
  hasInlineImages,
  isSyncAvailable,
  normalizeSyncKey,
  pushRemoteBoard,
  replaceImageUrls,
  setSyncKey,
  setSyncedAt,
  uploadInlineImages,
} from "@/lib/sync"

export type SyncStatus = "unavailable" | "off" | "syncing" | "synced" | "error"

const PUSH_DELAY_MS = 1500

interface Options {
  items: BoardItem[]
  maxZIndex: number
  isLoaded: boolean
  applyRemote: (items: BoardItem[], maxZIndex: number) => void
  replaceItems: (update: (items: BoardItem[]) => BoardItem[]) => void
}

// Last write wins. A device pulls whenever it opens or regains focus, and
// pushes shortly after each local edit.
export function useBoardSync({ items, maxZIndex, isLoaded, applyRemote, replaceItems }: Options) {
  const [syncKey, setKey] = useState<string | null>(null)
  const [status, setStatus] = useState<SyncStatus>("off")
  const [error, setError] = useState<string | null>(null)
  // Items arrays we set ourselves (remote pulls, image swaps) are not user edits
  const ownWrite = useRef<BoardItem[] | null>(null)
  const sawInitialItems = useRef(false)
  const dirty = useRef(false)
  const latest = useRef({ items, maxZIndex })
  latest.current = { items, maxZIndex }

  useEffect(() => {
    setKey(getSyncKey())
    isSyncAvailable().then((ok) => {
      if (!ok) setStatus("unavailable")
    })
  }, [])

  const pull = useCallback(
    async (key: string) => {
      setStatus("syncing")
      try {
        const remote = await fetchRemoteBoard(key)
        if (remote && remote.updatedAt > getSyncedAt() && !dirty.current) {
          ownWrite.current = remote.board.items
          applyRemote(remote.board.items, remote.board.maxZIndex || remote.board.items.length + 1)
          setSyncedAt(remote.updatedAt)
        }
        setStatus("synced")
        setError(null)
        return remote
      } catch (e) {
        setStatus("error")
        setError(e instanceof Error ? e.message : "Sync failed")
        return null
      }
    },
    [applyRemote]
  )

  const push = useCallback(
    async (key: string) => {
      setStatus("syncing")
      try {
        let { items: current, maxZIndex: z } = latest.current
        if (hasInlineImages(current)) {
          const uploaded = await uploadInlineImages(key, current)
          // Swap inline images for hosted ones locally too, so they upload once
          replaceItems((prev) => {
            const next = replaceImageUrls(prev, uploaded)
            ownWrite.current = next
            return next
          })
          current = replaceImageUrls(current, uploaded)
        }
        // Anything still inline was added mid-upload; the next push takes it
        const updatedAt = await pushRemoteBoard(key, {
          items: current.filter((i) => !i.content.startsWith("data:")),
          maxZIndex: z,
        })
        setSyncedAt(updatedAt)
        dirty.current = hasInlineImages(latest.current.items)
        setStatus("synced")
        setError(null)
      } catch (e) {
        setStatus("error")
        setError(e instanceof Error ? e.message : "Sync failed")
      }
    },
    [replaceItems]
  )

  // Pull on load and whenever the tab comes back into view
  useEffect(() => {
    if (!isLoaded || !syncKey) return
    pull(syncKey)
    const onVisible = () => {
      if (document.visibilityState === "visible") pull(syncKey)
    }
    document.addEventListener("visibilitychange", onVisible)
    return () => document.removeEventListener("visibilitychange", onVisible)
  }, [isLoaded, syncKey, pull])

  // Push local edits after a short pause
  useEffect(() => {
    if (!isLoaded || !syncKey) return
    // What was loaded from this device isn't an edit; let the pull decide first
    if (!sawInitialItems.current) {
      sawInitialItems.current = true
      return
    }
    if (ownWrite.current === items) {
      ownWrite.current = null
      return
    }
    dirty.current = true
    const timer = setTimeout(() => push(syncKey), PUSH_DELAY_MS)
    return () => clearTimeout(timer)
  }, [items, maxZIndex, isLoaded, syncKey, push])

  // Start syncing this board under a brand-new key
  const enable = useCallback(async () => {
    const key = generateSyncKey()
    setSyncKey(key)
    setSyncedAt(0)
    setKey(key)
    dirty.current = true
    await push(key)
    return key
  }, [push])

  // Join an existing key: the cloud board replaces what's on this device
  const connect = useCallback(
    async (input: string) => {
      const key = normalizeSyncKey(input)
      const remote = await fetchRemoteBoard(key)
      if (!remote) throw new Error("No board found for that key. Check it and try again.")
      setSyncKey(key)
      setSyncedAt(0)
      dirty.current = false
      ownWrite.current = remote.board.items
      applyRemote(remote.board.items, remote.board.maxZIndex || remote.board.items.length + 1)
      setSyncedAt(remote.updatedAt)
      setKey(key)
      setStatus("synced")
    },
    [applyRemote]
  )

  // Stop syncing on this device; the board stays here and in the cloud
  const disconnect = useCallback(async () => {
    await disableReminders(syncKey)
    setSyncKey(null)
    setSyncedAt(0)
    setKey(null)
    setStatus("off")
  }, [syncKey])

  // Remove the board and its images from the cloud for every device
  const deleteCloudCopy = useCallback(async () => {
    if (!syncKey) return
    await disableReminders(syncKey)
    await deleteRemoteBoard(syncKey)
    setSyncKey(null)
    setSyncedAt(0)
    setKey(null)
    setStatus("off")
  }, [syncKey])

  return {
    syncKey,
    status: status === "unavailable" ? status : syncKey ? status : "off",
    error,
    enable,
    connect,
    disconnect,
    deleteCloudCopy,
    syncNow: () => syncKey && push(syncKey),
  }
}
