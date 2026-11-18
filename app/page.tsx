import type { Metadata } from "next"
import { VisionBoard } from "@/components/vision-board"
import { LangProvider, type Lang } from "@/lib/i18n"

const SITE_URL = "https://visionboard.kemenystudio.com"

// Only an explicit ?lang= picks the server language, the same rule the
// client follows first, so the server's HTML and hydration agree
function explicitLang(param: string | string[] | undefined): Lang {
  const asked = Array.isArray(param) ? param[0] : param
  return asked === "es" ? "es" : "en"
}

const COPY: Record<Lang, { title: string; description: string; locale: string; alternate: string }> = {
  en: {
    title: "VisionBoard: your 2027 vision board, every day",
    description:
      "A free vision board app for your 2027 goals. Write what you want, add photos and words, and see your board every day on the web and on iPhone. No sign up needed.",
    locale: "en_US",
    alternate: "es_419",
  },
  es: {
    title: "VisionBoard: tu tablero de visión 2027, todos los días",
    description:
      "Una app gratis de tablero de visión para tus metas 2027. Escribe lo que quieres, agrega fotos y palabras, y mira tu tablero cada día en la web y en iPhone. Sin registrarte.",
    locale: "es_419",
    alternate: "en_US",
  },
}

type Props = { searchParams: Promise<{ lang?: string | string[] }> }

// The alternates point search engines to ?lang=, which renders that language
export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const lang = explicitLang((await searchParams).lang)
  const copy = COPY[lang]
  return {
    title: copy.title,
    description: copy.description,
    alternates: {
      canonical: lang === "es" ? "/?lang=es" : "/",
      languages: {
        en: "/?lang=en",
        es: "/?lang=es",
        "x-default": "/",
      },
    },
    openGraph: {
      type: "website",
      url: lang === "es" ? `${SITE_URL}/?lang=es` : SITE_URL,
      siteName: "VisionBoard",
      title: copy.title,
      description: copy.description,
      locale: copy.locale,
      alternateLocale: [copy.alternate],
    },
    twitter: {
      card: "summary_large_image",
      title: copy.title,
      description: copy.description,
    },
  }
}

export default async function Home({ searchParams }: Props) {
  const lang = explicitLang((await searchParams).lang)
  return (
    <LangProvider lang={lang}>
      <VisionBoard />
    </LangProvider>
  )
}
