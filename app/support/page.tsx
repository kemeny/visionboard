import type { Metadata } from 'next'
import { LegalPage } from '@/components/legal-page'
import { SUPPORT, pickLang } from '@/lib/legal'

export const metadata: Metadata = {
  title: 'Support · VisionBoard',
  description: SUPPORT.en.intro,
}

export default async function SupportPage({ searchParams }: { searchParams: Promise<{ lang?: string | string[] }> }) {
  const lang = await pickLang((await searchParams).lang)
  return <LegalPage doc={SUPPORT[lang]} lang={lang} path="/support" />
}
