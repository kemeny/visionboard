"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Heart, X } from "lucide-react"
import { BoardItem } from "@/lib/types"
import { buildFeedRound, loadFeedStats, recordView, saveFeedStats, type FeedStats } from "@/lib/feed"
import { getTextStyle } from "./board-item"
import { cn } from "@/lib/utils"

type Tab = "foryou" | "liked"

// Cards near the one on screen get real content; the rest are empty slides
// so an endless feed stays light
const RENDER_WINDOW = 2
// Under this, a glance doesn't count as a view
const MIN_VIEW_MS = 600

interface Props {
  items: BoardItem[]
  onToggleLike: (id: string, liked: boolean) => void
  onClose: () => void
}

export function FeedView({ items, onToggleLike, onClose }: Props) {
  const [tab, setTab] = useState<Tab>("foryou")
  const [feed, setFeed] = useState<BoardItem[]>([])
  const [index, setIndex] = useState(0)
  const [burst, setBurst] = useState<{ key: number; index: number } | null>(null)
  const scrollRef = useRef<HTMLDivElement>(null)
  const stats = useRef<FeedStats>({})
  const shownAt = useRef(Date.now())
  const lastTap = useRef(0)

  // Likes change while the feed is open; read them live rather than from the snapshot
  const liked = useMemo(() => new Set(items.filter((i) => i.liked).map((i) => i.id)), [items])

  const nextRound = useCallback(
    (avoid: string[]) => buildFeedRound(items, stats.current, { avoid, likedOnly: tab === "liked" }),
    [items, tab]
  )

  // New order each time the feed opens or the tab changes
  useEffect(() => {
    stats.current = loadFeedStats()
    setFeed(buildFeedRound(items, stats.current, { likedOnly: tab === "liked" }))
    setIndex(0)
    shownAt.current = Date.now()
    scrollRef.current?.scrollTo({ top: 0 })
    // Only on open and tab switch: a like mid-scroll shouldn't reshuffle the feed
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab])

  const logView = useCallback(
    (i: number) => {
      const item = feed[i]
      const dwell = Date.now() - shownAt.current
      if (!item || dwell < MIN_VIEW_MS) return
      stats.current = recordView(stats.current, item.id, Math.min(dwell, 60_000))
      saveFeedStats(stats.current)
    },
    [feed]
  )

  const onScroll = () => {
    const el = scrollRef.current
    if (!el) return
    const i = Math.round(el.scrollTop / el.clientHeight)
    if (i === index) return
    logView(index)
    shownAt.current = Date.now()
    setIndex(i)
    // Endless: queue another round before the end comes into view
    if (i >= feed.length - 3 && feed.length) {
      setFeed((f) => [...f, ...nextRound(f.slice(-3).map((x) => x.id))])
    }
  }

  const close = () => {
    logView(index)
    onClose()
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && close()
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  })

  const like = (i: number) => {
    const item = feed[i]
    if (!item) return
    onToggleLike(item.id, !liked.has(item.id))
  }

  // Double-tap to like, like Instagram: it only ever adds a like
  const onCardTap = (i: number) => {
    const now = Date.now()
    if (now - lastTap.current < 300) {
      const item = feed[i]
      if (item && !liked.has(item.id)) onToggleLike(item.id, true)
      setBurst({ key: now, index: i })
      setTimeout(() => setBurst((b) => (b?.key === now ? null : b)), 800)
      lastTap.current = 0
    } else {
      lastTap.current = now
    }
  }

  return (
    <div className="fixed inset-0 z-[90] bg-black text-white" role="dialog" aria-label="Feed">
      <div className="pointer-events-none absolute inset-x-0 top-0 z-10 flex items-center justify-between bg-gradient-to-b from-black/60 to-transparent px-4 pb-6 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <button aria-label="Back to board" className="pointer-events-auto rounded-full p-1.5" onClick={close}>
          <X className="h-6 w-6" />
        </button>
        <div className="pointer-events-auto flex gap-5 text-sm font-semibold">
          {(["foryou", "liked"] as Tab[]).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cn("pb-1 transition-opacity", tab === t ? "border-b-2 border-white" : "opacity-60")}
            >
              {t === "foryou" ? "For you" : "Liked"}
            </button>
          ))}
        </div>
        <div className="w-9" />
      </div>

      {feed.length === 0 ? (
        <div className="flex h-full flex-col items-center justify-center gap-2 px-8 text-center">
          <Heart className="h-10 w-10 opacity-60" />
          <p className="text-lg font-semibold">
            {tab === "liked" ? "Nothing liked yet" : "Your board is empty"}
          </p>
          <p className="text-sm text-white/60">
            {tab === "liked"
              ? "Double-tap clippings you love in For you, and they'll collect here."
              : "Add photos and words to your board to fill your feed."}
          </p>
        </div>
      ) : (
        <div
          ref={scrollRef}
          onScroll={onScroll}
          className="h-full snap-y snap-mandatory overflow-y-scroll overscroll-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        >
          {feed.map((item, i) => (
            <section
              key={`${item.id}-${i}`}
              className="relative h-full w-full snap-start snap-always overflow-hidden"
              onClick={() => onCardTap(i)}
            >
              {Math.abs(i - index) <= RENDER_WINDOW && <FeedCard item={item} />}

              {burst?.index === i && (
                <Heart
                  key={burst.key}
                  className="pointer-events-none absolute left-1/2 top-1/2 h-28 w-28 -translate-x-1/2 -translate-y-1/2 fill-white text-white drop-shadow-lg animate-in zoom-in-50 fade-in duration-300"
                />
              )}

              <div className="absolute bottom-[max(1.5rem,env(safe-area-inset-bottom))] right-4 flex flex-col items-center gap-1">
                <button
                  aria-label={liked.has(item.id) ? "Unlike" : "Like"}
                  aria-pressed={liked.has(item.id)}
                  className="rounded-full p-2 transition-transform active:scale-90"
                  onClick={(e) => {
                    e.stopPropagation()
                    like(i)
                  }}
                >
                  <Heart
                    className={cn(
                      "h-8 w-8 drop-shadow",
                      liked.has(item.id) ? "fill-red-500 text-red-500" : "text-white"
                    )}
                  />
                </button>
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  )
}

function FeedCard({ item }: { item: BoardItem }) {
  if (item.type === "image") {
    return (
      <>
        {/* Blurred copy fills the screen behind the whole, uncropped clipping */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={item.content} alt="" className="absolute inset-0 h-full w-full scale-110 object-cover opacity-60 blur-2xl" />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={item.content} alt="" className="absolute inset-0 h-full w-full object-contain" draggable={false} />
      </>
    )
  }

  const style = getTextStyle(item.fontStyle)
  const hasBg = item.bgColor && item.bgColor !== "transparent"
  return (
    <div
      className="flex h-full w-full items-center justify-center px-8"
      style={{ background: hasBg ? item.bgColor : "linear-gradient(160deg, #f5f0e8, #e7dccb)" }}
    >
      <p
        className="max-w-xl text-center"
        style={{
          color: item.color || "#1a1a1a",
          fontFamily: style.fontFamily,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          letterSpacing: style.letterSpacing,
          lineHeight: style.lineHeight,
          textTransform: style.textTransform as React.CSSProperties["textTransform"],
          // Scale with the text so a short goal fills the card and a long one still fits
          fontSize: `clamp(1.5rem, ${Math.max(5, 14 - item.content.length / 12)}vw, 3.5rem)`,
        }}
      >
        {item.content}
      </p>
    </div>
  )
}
