"use client"

import { useState } from "react"
import { Check, Loader2, Search } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { track } from "@/lib/analytics"
import { useT, type MessageKey } from "@/lib/i18n"
import { UNSPLASH_REFERRAL_URL, safeCreditUrl, type ImageCredit } from "@/lib/types"

// One Unsplash result, as the Worker's /api/sync/ai/photos returns it
export interface SearchPhoto {
  imageUrl: string
  thumbUrl: string
  width: number
  height: number
  alt: string | null
  photographer: string | null
  photographerUrl: string | null
  unsplashDownloadUrl: string | null
}

export interface PickedPhoto {
  imageUrl: string
  aspect: number
  credit?: ImageCredit
}

const IDEAS_EN = ["beach house", "running", "Japan", "healthy food", "home office", "mountains"]
const IDEAS_ES = ["casa en la playa", "correr", "Japón", "comida sana", "oficina en casa", "montañas"]

async function post(path: string, body: unknown): Promise<Response> {
  return fetch(`/api/sync${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-VB-Client": "web" },
    body: JSON.stringify(body),
  })
}

const ERRORS: Record<string, MessageKey> = {
  rate_limited: "photos.err.rate",
  ai_unavailable: "photos.err.off",
}

export function PhotoSearchDialog({
  open,
  onOpenChange,
  onAdd,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  onAdd: (photos: PickedPhoto[]) => void
}) {
  const { t, lang } = useT()
  const [query, setQuery] = useState("")
  const [searched, setSearched] = useState("")
  const [photos, setPhotos] = useState<SearchPhoto[]>([])
  const [page, setPage] = useState(1)
  const [hasMore, setHasMore] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<MessageKey | null>(null)
  const [picked, setPicked] = useState<string[]>([])

  // Start fresh next time: clear everything when it closes
  const setOpen = (next: boolean) => {
    if (!next) {
      setQuery("")
      setSearched("")
      setPhotos([])
      setPicked([])
      setError(null)
      setHasMore(false)
    }
    onOpenChange(next)
  }

  const run = async (words: string, nextPage = 1) => {
    const q = words.trim().replace(/\s+/g, " ").slice(0, 80)
    if (!q || loading) return
    setLoading(true)
    setError(null)
    if (nextPage === 1) {
      setPhotos([])
      setPicked([])
    }
    try {
      const response = await post("/ai/photos", { query: q, page: nextPage })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) {
        setError(ERRORS[data?.error] || "photos.err.generic")
        track("photo_search_failed", { reason: data?.error || `http_${response.status}` })
        return
      }
      const found: SearchPhoto[] = Array.isArray(data.photos) ? data.photos : []
      setPhotos((prev) => (nextPage === 1 ? found : [...prev, ...found]))
      setHasMore(Boolean(data.hasMore))
      setPage(nextPage)
      setSearched(q)
      if (nextPage === 1) track("photo_searched", { results: found.length })
    } catch {
      setError("photos.err.generic")
      track("photo_search_failed", { reason: "network" })
    } finally {
      setLoading(false)
    }
  }

  const toggle = (url: string) =>
    setPicked((prev) => (prev.includes(url) ? prev.filter((u) => u !== url) : [...prev, url]))

  const add = () => {
    const chosen = picked
      .map((url) => photos.find((p) => p.imageUrl === url))
      .filter((p): p is SearchPhoto => !!p)
    if (!chosen.length) return
    onAdd(
      chosen.map((p) => ({
        imageUrl: p.imageUrl,
        aspect: p.width / p.height,
        credit: p.photographer
          ? { name: p.photographer, url: p.photographerUrl || undefined, source: "unsplash" }
          : undefined,
      }))
    )
    // Unsplash asks apps to report each photo they actually use. Best effort.
    for (const p of chosen) {
      if (p.unsplashDownloadUrl) post("/ai/unsplash-download", { url: p.unsplashDownloadUrl }).catch(() => {})
    }
    setOpen(false)
  }

  const ideas = lang === "es" ? IDEAS_ES : IDEAS_EN

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="flex max-h-[90dvh] flex-col gap-3 sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{t("photos.title")}</DialogTitle>
          <DialogDescription>{t("photos.description")}</DialogDescription>
        </DialogHeader>

        <form
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault()
            run(query)
          }}
        >
          <Input
            autoFocus
            value={query}
            maxLength={80}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t("photos.placeholder")}
            aria-label={t("photos.title")}
          />
          <Button type="submit" disabled={!query.trim() || loading}>
            {loading && page === 1 ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
            <span className="sr-only sm:not-sr-only sm:ml-1">{t("photos.search")}</span>
          </Button>
        </form>

        {!searched && !loading && !error && (
          <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <span>{t("photos.ideas")}</span>
            {ideas.map((idea) => (
              <button
                key={idea}
                type="button"
                className="rounded-full border px-3 py-1 text-foreground hover:bg-muted"
                onClick={() => {
                  setQuery(idea)
                  run(idea)
                }}
              >
                {idea}
              </button>
            ))}
          </div>
        )}

        {error && <p className="text-sm text-destructive">{t(error)}</p>}
        {searched && !loading && !error && photos.length === 0 && (
          <p className="text-sm text-muted-foreground">{t("photos.empty")}</p>
        )}

        {photos.length > 0 && (
          <div className="-mx-1 min-h-0 flex-1 overflow-y-auto px-1">
            <div className="columns-2 gap-2 sm:columns-3">
              {photos.map((photo) => {
                const index = picked.indexOf(photo.imageUrl)
                const profile = safeCreditUrl(photo.photographerUrl || undefined)
                return (
                  <div key={photo.imageUrl} className="mb-2 break-inside-avoid">
                    <button
                      type="button"
                      onClick={() => toggle(photo.imageUrl)}
                      aria-pressed={index >= 0}
                      className={`relative block w-full overflow-hidden rounded-md ring-offset-2 ring-offset-background ${
                        index >= 0 ? "ring-2 ring-primary" : ""
                      }`}
                      style={{ aspectRatio: `${photo.width} / ${photo.height}` }}
                    >
                      {/* Hotlinked from Unsplash's CDN, as their API guidelines ask */}
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={photo.thumbUrl} alt={photo.alt || ""} loading="lazy" className="h-full w-full object-cover" />
                      {index >= 0 && (
                        <span className="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-full bg-primary text-primary-foreground">
                          <Check className="h-4 w-4" />
                        </span>
                      )}
                    </button>
                    {photo.photographer && (
                      <p className="mt-0.5 truncate text-[11px] text-muted-foreground">
                        {profile ? (
                          <a href={profile} target="_blank" rel="noopener noreferrer" className="underline">
                            {photo.photographer}
                          </a>
                        ) : (
                          photo.photographer
                        )}{" "}
                        {t("photos.on")}{" "}
                        <a href={UNSPLASH_REFERRAL_URL} target="_blank" rel="noopener noreferrer" className="underline">
                          Unsplash
                        </a>
                      </p>
                    )}
                  </div>
                )
              })}
            </div>
            {hasMore && (
              <div className="flex justify-center py-2">
                <Button variant="ghost" size="sm" disabled={loading} onClick={() => run(searched, page + 1)}>
                  {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : t("photos.more")}
                </Button>
              </div>
            )}
          </div>
        )}

        <div className="flex justify-end">
          <Button onClick={add} disabled={picked.length === 0}>
            {t("photos.add", { count: picked.length })}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
