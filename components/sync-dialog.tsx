"use client"

import { useEffect, useState } from "react"
import { Bell, Check, Cloud, Copy, Loader2 } from "lucide-react"
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
  pushSupported,
  sendTestReminder,
} from "@/lib/sync"
import type { useBoardSync } from "@/hooks/use-board-sync"

type Sync = ReturnType<typeof useBoardSync>

const HOURS = Array.from({ length: 24 }, (_, h) => h)
const formatHour = (h: number) =>
  new Date(2000, 0, 1, h).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })

export function SyncDialog({ open, onOpenChange, sync }: { open: boolean; onOpenChange: (o: boolean) => void; sync: Sync }) {
  const [joinKey, setJoinKey] = useState("")
  const [busy, setBusy] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [reminderOn, setReminderOn] = useState(false)
  const [hour, setHour] = useState(8)

  useEffect(() => {
    if (!open) return
    const pref = getReminderPref()
    setReminderOn(!!pref)
    if (pref) setHour(pref.hour)
    setMessage(null)
  }, [open])

  const run = async (label: string, fn: () => Promise<unknown>) => {
    setBusy(label)
    setMessage(null)
    try {
      await fn()
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Something went wrong")
    } finally {
      setBusy(null)
    }
  }

  const copyKey = async () => {
    if (!sync.syncKey) return
    await navigator.clipboard.writeText(sync.syncKey)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
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

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
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
                    {sync.status === "syncing" ? "Saving…" : sync.status === "error" ? "Offline, will retry" : "Saved"}
                  </span>
                )}
              </h3>

              {sync.syncKey ? (
                <>
                  <p className="text-xs text-muted-foreground">
                    Your sync key. Enter it on another device to open this board there. Keep it private: anyone with
                    it can see and edit your board, and it can&apos;t be recovered if lost.
                  </p>
                  <div className="flex gap-2">
                    <code className="flex-1 rounded-md border bg-muted px-3 py-2 text-xs break-all">{sync.syncKey}</code>
                    <Button variant="outline" size="sm" className="h-auto" onClick={copyKey}>
                      {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
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
                  <Button className="w-full" disabled={!!busy} onClick={() => run("enable", sync.enable)}>
                    {busy === "enable" && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Turn on sync for this board
                  </Button>
                  <div className="flex gap-2">
                    <Input
                      placeholder="Have a key? Paste it here"
                      value={joinKey}
                      onChange={(e) => setJoinKey(e.target.value)}
                      className="text-xs"
                    />
                    <Button
                      variant="outline"
                      disabled={!joinKey.trim() || !!busy}
                      onClick={() => {
                        if (window.confirm("Open the synced board here? It replaces the board on this device."))
                          run("connect", () => sync.connect(joinKey))
                      }}
                    >
                      {busy === "connect" ? <Loader2 className="h-4 w-4 animate-spin" /> : "Open"}
                    </Button>
                  </div>
                </>
              )}
            </section>

            <section className="space-y-3">
              <h3 className="flex items-center gap-2 text-sm font-medium">
                <Bell className="h-4 w-4" /> Daily reminder
              </h3>
              {iosNeedsInstall ? (
                <p className="text-xs text-muted-foreground">
                  On iPhone, tap Share, then &quot;Add to Home Screen&quot;, and open Vision Board from there to turn on
                  reminders.
                </p>
              ) : !pushSupported() ? (
                <p className="text-xs text-muted-foreground">This browser doesn&apos;t support notifications.</p>
              ) : (
                <>
                  <p className="text-xs text-muted-foreground">
                    One notification a day with something from your board. Turning this on also turns on sync.
                  </p>
                  <div className="flex items-center gap-3">
                    <Switch checked={reminderOn} disabled={!!busy} onCheckedChange={toggleReminder} />
                    <select
                      className="rounded-md border bg-background px-2 py-1 text-sm"
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
                        onClick={() => run("test", () => sendTestReminder(sync.syncKey!))}
                      >
                        Send a test
                      </Button>
                    )}
                  </div>
                </>
              )}
            </section>

            {(message || sync.error) && <p className="text-xs text-destructive">{message || sync.error}</p>}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
