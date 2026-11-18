import type { Metadata } from 'next'
import { LegalPage } from '@/components/legal-page'
import { PRIVACY, pickLang } from '@/lib/legal'

export const metadata: Metadata = {
  title: 'Privacy · VisionBoard',
  description: PRIVACY.en.intro,
}

export default async function PrivacyPage({ searchParams }: { searchParams: Promise<{ lang?: string | string[] }> }) {
  const lang = await pickLang((await searchParams).lang)
  return <LegalPage doc={PRIVACY[lang]} lang={lang} path="/privacy" />
}
