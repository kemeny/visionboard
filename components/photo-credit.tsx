"use client"

import { type ImageCredit, UNSPLASH_REFERRAL_URL, safeCreditUrl } from "@/lib/types"
import { useT } from "@/lib/i18n"
import { cn } from "@/lib/utils"

// "Photo by X on Unsplash". Shown wherever a credited photo appears large:
// the selection toolbar, the feed and today's card. Links only to unsplash.com.
export function PhotoCredit({ credit, className }: { credit: ImageCredit; className?: string }) {
  const { t } = useT()
  const profile = safeCreditUrl(credit.url)
  const stop = (e: React.MouseEvent) => e.stopPropagation()
  return (
    <span className={cn("whitespace-nowrap", className)}>
      {t("credit.photoBy")}{" "}
      {profile ? (
        <a href={profile} target="_blank" rel="noopener noreferrer" className="underline" onClick={stop}>
          {credit.name}
        </a>
      ) : (
        credit.name
      )}
      {credit.source === "unsplash" && (
        <>
          {" "}{t("credit.on")}{" "}
          <a href={UNSPLASH_REFERRAL_URL} target="_blank" rel="noopener noreferrer" className="underline" onClick={stop}>
            Unsplash
          </a>
        </>
      )}
    </span>
  )
}
