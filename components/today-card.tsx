"use client"

import { X } from "lucide-react"
import type { TodayCard as TodayCardData } from "@/lib/sync"

// Full-screen view of today's reminder: the photo with the goal over it.
// Tapping anywhere goes back to the board.
export function TodayCard({ card, onClose }: { card: TodayCardData; onClose: () => void }) {
  return (
    <div
      role="dialog"
      aria-label="Today's reminder"
      className="fixed inset-0 z-[100] flex cursor-pointer flex-col justify-end bg-[#1a1714] text-white"
      onClick={onClose}
    >
      {card.image && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={card.image} alt="" className="absolute inset-0 h-full w-full object-cover" />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />

      <button
        aria-label="Close"
        className="absolute right-4 top-[max(1rem,env(safe-area-inset-top))] rounded-full bg-black/40 p-2 backdrop-blur"
        onClick={onClose}
      >
        <X className="h-5 w-5" />
      </button>

      <div className="relative px-6 pb-[max(2.5rem,env(safe-area-inset-bottom))] pt-24">
        <p className="mb-3 text-xs font-medium uppercase tracking-[0.2em] text-white/70">Today</p>
        {card.text && (
          <p className="text-3xl font-bold leading-tight tracking-tight sm:text-5xl">{card.text}</p>
        )}
        <p className="mt-6 text-sm text-white/60">Tap to see your board</p>
      </div>
    </div>
  )
}
