import type { Metadata } from 'next'
import { LegalPage } from '@/components/legal-page'
import { TERMS, pickLang } from '@/lib/legal'

export const metadata: Metadata = {
  title: 'Terms · VisionBoard',
  description: TERMS.en.intro,
}

export default async function TermsPage({ searchParams }: { searchParams: Promise<{ lang?: string | string[] }> }) {
  const lang = await pickLang((await searchParams).lang)
  return <LegalPage doc={TERMS[lang]} lang={lang} path="/terms" />
}
