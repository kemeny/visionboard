import Link from 'next/link'
import { type Lang, type LegalDoc, UI, UPDATED } from '@/lib/legal'

// Plain reading page shared by /privacy, /terms and /support
export function LegalPage({ doc, lang, path }: { doc: LegalDoc; lang: Lang; path: string }) {
  const ui = UI[lang]
  return (
    <main lang={lang} className="min-h-screen bg-background text-foreground">
      <div className="mx-auto max-w-2xl px-4 py-10 sm:py-16">
        <nav className="mb-10 flex flex-wrap items-center justify-between gap-3 text-sm">
          <Link href="/" className="text-muted-foreground hover:text-foreground">
            {ui.back}
          </Link>
          <div className="flex flex-wrap gap-4">
            <Link href={`/privacy?lang=${lang}`} className="text-muted-foreground hover:text-foreground">{ui.nav.privacy}</Link>
            <Link href={`/terms?lang=${lang}`} className="text-muted-foreground hover:text-foreground">{ui.nav.terms}</Link>
            <Link href={`/support?lang=${lang}`} className="text-muted-foreground hover:text-foreground">{ui.nav.support}</Link>
            <Link href={`${path}?lang=${ui.otherLang}`} className="font-medium">{ui.other}</Link>
          </div>
        </nav>
        <h1 className="text-3xl font-semibold tracking-tight">{doc.title}</h1>
        <p className="mt-4 text-base leading-relaxed text-muted-foreground">{doc.intro}</p>
        {doc.sections.map((section) => (
          <section key={section.heading} className="mt-10">
            <h2 className="text-lg font-semibold">{section.heading}</h2>
            {section.body.map((p, i) => (
              <p key={i} className="mt-3 leading-relaxed">{p}</p>
            ))}
          </section>
        ))}
        <p className="mt-12 text-sm text-muted-foreground">
          {ui.updated}: {UPDATED}
        </p>
      </div>
    </main>
  )
}
