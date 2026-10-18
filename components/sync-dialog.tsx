"use client"

import { useEffect, useRef, useState } from "react"
import QRCode from "qrcode"
import { Bell, Check, ClipboardPaste, Cloud, Copy, Loader2, Send, Smartphone } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  disableReminders,
  enableReminders,
  getReminderPref,
  isIos,
  isStandalone,
  normalizeSyncKey,
  pushSupported,
  sendTestReminder,
  syncLink,
} from "@/lib/sync"
import type { useBoardSync } from "@/hooks/use-board-sync"

type Sync = ReturnType<typeof useBoardSync>

const HOURS = Array.from({ length: 24 }, (_, h) => h)
const formatHour = (h: number) =>
  new Date(2000, 0, 1, h).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })

interface Props {
  open: boolean
  onOpenChange: (o: boolean) => void
  sync: Sync
  hasLocalItems: boolean
  // Key from a "#sync=" link this page was opened with
  linkKey: string | null
  onLinkHandled: () => void
}

export function SyncDialog({ open, onOpenChange, sync, hasLocalItems, linkKey, onLinkHandled }: Props) {
  const [joinKey, setJoinKey] = useState("")
  const [busy, setBusy] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [copied, setCopied] = useState<"key" | "link" | null>(null)
  const [reminderOn, setReminderOn] = useState(false)
  const [hour, setHour] = useState(8)
  const [qr, setQr] = useState<string | null>(null)
  const handledLink = useRef<string | null>(null)

  useEffect(() => {
    if (!open) return
    const pref = getReminderPref()
    setReminderOn(!!pref)
    if (pref) setHour(pref.hour)
    setMessage(null)
  }, [open])

  useEffect(() => {
    if (!sync.syncKey) return setQr(null)
    QRCode.toDataURL(syncLink(sync.syncKey), { margin: 1, width: 360 })
      .then(setQr)
      .catch(() => setQr(null))
  }, [sync.syncKey])

  const run = async (label: string, fn: () => Promise<unknown>) => {
    setBusy(label)
    setMessage(null)
    setNotice(null)
    try {
      await fn()
      return true
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Something went wrong")
      return false
    } finally {
      setBusy(null)
    }
  }

  const afterJoin = () => {
    // iPhone keeps Home Screen apps separate from Safari, so the key is needed once more there
    if (isIos() && !isStandalone()) {
      setNotice(
        'Board opened. For daily reminders: tap Copy key below, then Share → "Add to Home Screen", open it from there and tap Paste.'
      )
    } else {
      onOpenChange(false)
    }
  }

  const join = async (key: string) => {
    const k = normalizeSyncKey(key)
    if (!k) return
    if (k === sync.syncKey) return setNotice("This board is already open on this device.")
    if (hasLocalItems && !window.confirm("Open your synced board here? It replaces what's on this device.")) return
    if (await run("connect", () => sync.connect(k))) afterJoin()
  }

  // Opened from a "#sync=" link or QR code: connect straight away
  useEffect(() => {
    if (!open || !linkKey || handledLink.current === linkKey || sync.status === "unavailable") return
    handledLink.current = linkKey
    setJoinKey(linkKey)
    onLinkHandled()
    join(linkKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, linkKey, sync.status])

  const copy = async (what: "key" | "link") => {
    if (!sync.syncKey) return
    await navigator.clipboard.writeText(what === "key" ? sync.syncKey : syncLink(sync.syncKey))
    setCopied(what)
    setTimeout(() => setCopied(null), 1500)
  }

  const sendLink = async () => {
    if (!sync.syncKey) return
    const url = syncLink(sync.syncKey)
    if (navigator.share) {
      try {
        await navigator.share({ title: "My vision board", url })
        return
      } catch (e) {
        if (e instanceof DOMException && e.name === "AbortError") return
      }
    }
    await copy("link")
  }

  const paste = async () => {
    try {
      const text = await navigator.clipboard.readText()
      // Accept a pasted link as well as a bare key
      const fromLink = text.match(/#sync=([^&\s]+)/)
      setJoinKey(fromLink ? decodeURIComponent(fromLink[1]) : text.trim())
    } catch {
      setMessage("Couldn't read the clipboard. Long-press the box and choose Paste.")
    }
  }

  const ensureKey = async () => sync.syncKey ?? (await sync.enable())

  const toggleReminder = (on: boolean) =>
    run("reminder", async () => {
      if (on) {
        await enableReminders(await ensureKey(), hour)
        setReminderOn(true)
      } else {
        await disableReminders(sync.syncKey)
        setReminderOn(false)
      }
    })

  const changeHour = (h: number) => {
    setHour(h)
    if (reminderOn && sync.syncKey) run("reminder", () => enableReminders(sync.syncKey!, h))
  }

  const iosNeedsInstall = isIos() && !pushSupported()
  const canPaste = typeof navigator !== "undefined" && !!navigator.clipboard?.readText

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Sync & reminders</DialogTitle>
          <DialogDescription>
            Keep your board safe in the cloud, open it on any device, and get a daily nudge.
          </DialogDescription>
        </DialogHeader>

        {sync.status === "unavailable" ? (
          <p className="text-sm text-muted-foreground">Sync isn&apos;t set up on this site yet.</p>
        ) : (
          <div className="space-y-6">
            <section className="space-y-3">
              <h3 className="flex items-center gap-2 text-sm font-medium">
                <Cloud className="h-4 w-4" /> Cloud sync
                {sync.syncKey && (
                  <span className="ml-auto text-xs font-normal text-muted-foreground">
                    {sync.status === "syncing" ? "Saving…" : sync.status === "error" ? "Not fully saved" : "Saved"}
                  </span>
                )}
              </h3>

              {sync.syncKey ? (
                <>
                  <div className="flex flex-col items-center gap-3 rounded-lg border bg-muted/40 p-4 sm:flex-row sm:items-start">
                    {qr && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={qr}
                        alt="QR code that opens this board"
                        className="hidden h-32 w-32 shrink-0 rounded-md bg-white sm:block"
                      />
                    )}
                    <div className="w-full space-y-2 text-center sm:text-left">
                      <p className="flex items-center justify-center gap-1.5 text-sm font-medium sm:justify-start">
                        <Smartphone className="h-4 w-4" /> Open on another device
                      </p>
                      <p className="text-xs text-muted-foreground">
                        <span className="hidden sm:inline">Scan with your phone&apos;s camera, or send the link. </span>
                        Anyone with the link can see and edit your board, so keep it to yourself.
                      </p>
                      <Button size="sm" className="w-full sm:w-auto" onClick={sendLink}>
                        {copied === "link" ? <Check className="mr-1.5 h-4 w-4" /> : <Send className="mr-1.5 h-4 w-4" />}
                        {copied === "link" ? "Link copied" : "Send link"}
                      </Button>
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <code className="flex-1 rounded-md border bg-muted px-3 py-2 font-mono text-xs break-all">
                      {sync.syncKey}
                    </code>
                    <Button variant="outline" size="sm" className="h-9 shrink-0" onClick={() => copy("key")}>
                      {copied === "key" ? <Check className="mr-1.5 h-4 w-4" /> : <Copy className="mr-1.5 h-4 w-4" />}
                      Copy key
                    </Button>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <Button variant="ghost" size="sm" className="text-xs" onClick={() => run("disconnect", sync.disconnect)}>
                      Stop syncing this device
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-xs text-destructive hover:text-destructive"
                      onClick={() => {
                        if (window.confirm("Delete the cloud copy for every device? The board stays on this device."))
                          run("delete", sync.deleteCloudCopy)
                      }}
                    >
                      Delete cloud copy
                    </Button>
                  </div>
                </>
              ) : (
                <>
                  <div className="space-y-2 rounded-lg border bg-muted/40 p-4">
                    <p className="text-sm font-medium">Already synced on another device?</p>
                    <p className="text-xs text-muted-foreground">
                      Scan the QR code shown there, open the link you sent yourself, or paste the key.
                    </p>
                    <div className="flex gap-2">
                      <Input
                        placeholder="xxxx-xxxx-xxxx-xxxx-xxxx"
                        value={joinKey}
                        onChange={(e) => setJoinKey(e.target.value)}
                        autoComplete="off"
                        autoCorrect="off"
                        autoCapitalize="none"
                        spellCheck={false}
                        // 16px on phones so iOS doesn't zoom the page when focused
                        className="font-mono text-base sm:text-sm"
                      />
                      {canPaste && !joinKey && (
                        <Button variant="outline" className="shrink-0" onClick={paste}>
                          <ClipboardPaste className="mr-1.5 h-4 w-4" /> Paste
                        </Button>
                      )}
                      {!!joinKey && (
                        <Button className="shrink-0" disabled={!!busy} onClick={() => join(joinKey)}>
                          {busy === "connect" ? <Loader2 className="h-4 w-4 animate-spin" /> : "Open"}
                        </Button>
                      )}
                    </div>
                  </div>
                  <Button
                    variant="outline"
                    className="w-full"
                    disabled={!!busy}
                    onClick={() => run("enable", sync.enable)}
                  >
                    {busy === "enable" && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Start syncing the board on this device
                  </Button>
                </>
              )}
            </section>

            <section className="space-y-3">
              <h3 className="flex items-center gap-2 text-sm font-medium">
                <Bell className="h-4 w-4" /> Daily reminder
              </h3>
              {iosNeedsInstall ? (
                <ol className="list-decimal space-y-1 pl-4 text-xs text-muted-foreground">
                  <li>Tap Share in Safari, then &quot;Add to Home Screen&quot;.</li>
                  <li>Open Vision Board from your Home Screen.</li>
                  <li>Paste your key there and turn on the reminder.</li>
                </ol>
              ) : !pushSupported() ? (
                <p className="text-xs text-muted-foreground">This browser doesn&apos;t support notifications.</p>
              ) : (
                <>
                  <p className="text-xs text-muted-foreground">
                    One notification a day with something from your board. Turning this on also turns on sync.
                  </p>
                  <div className="flex flex-wrap items-center gap-3">
                    <Switch checked={reminderOn} disabled={!!busy} onCheckedChange={toggleReminder} />
                    <select
                      className="rounded-md border bg-background px-2 py-1 text-base sm:text-sm"
                      value={hour}
                      onChange={(e) => changeHour(Number(e.target.value))}
                    >
                      {HOURS.map((h) => (
                        <option key={h} value={h}>
                          {formatHour(h)}
                        </option>
                      ))}
                    </select>
                    {busy === "reminder" && <Loader2 className="h-4 w-4 animate-spin" />}
                    {reminderOn && sync.syncKey && (
                      <Button
                        variant="ghost"
                        size="sm"
                        className="ml-auto text-xs"
                        disabled={!!busy}
                        onClick={async () => {
                          if (await run("test", () => sendTestReminder(sync.syncKey!)))
                            setNotice("Test sent. It should arrive in a few seconds.")
                        }}
                      >
                        Send a test
                      </Button>
                    )}
                  </div>
                </>
              )}
            </section>

            {notice && <p className="text-xs text-emerald-700">{notice}</p>}
            {(message || sync.error) && <p className="text-xs text-destructive">{message || sync.error}</p>}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
