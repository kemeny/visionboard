import type { Metadata } from "next"
import { VisionBoard } from "@/components/vision-board"

// The board picks its language on the client; ?lang= forces one, which is
// what the alternates point search engines to
export const metadata: Metadata = {
  alternates: {
    canonical: "/",
    languages: {
      en: "/?lang=en",
      es: "/?lang=es",
      "x-default": "/",
    },
  },
}

export default function Home() {
  return <VisionBoard />
}
