import type { Metadata } from 'next'
import { Geist, Geist_Mono } from 'next/font/google'
import { Analytics } from '@vercel/analytics/next'
import { AnalyticsProvider } from '@/components/analytics-provider'
import './globals.css'

const _geist = Geist({ subsets: ["latin"] });
const _geistMono = Geist_Mono({ subsets: ["latin"] });

const SITE_URL = 'https://visionboard.kemenystudio.com'
const TITLE = 'VisionBoard: your 2027 vision board, every day'
const DESCRIPTION =
  'A free vision board app for your 2027 goals. Write what you want, add photos and words, and see your board every day on the web and on iPhone. No sign up needed.'
const APP_STORE_ID = process.env.NEXT_PUBLIC_APP_STORE_ID

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: TITLE,
  description: DESCRIPTION,
  applicationName: 'VisionBoard',
  keywords: [
    'vision board',
    'vision board 2027',
    'vision board app',
    'free vision board',
    '2027 goals',
    'New Year goals',
    'goal setting',
    'manifestation board',
    'dream board',
    'tablero de visión',
    'vision board 2027 gratis',
    'metas 2027',
  ],
  openGraph: {
    type: 'website',
    url: SITE_URL,
    siteName: 'VisionBoard',
    title: TITLE,
    description: DESCRIPTION,
    locale: 'en_US',
    alternateLocale: ['es_419'],
  },
  twitter: {
    card: 'summary_large_image',
    title: TITLE,
    description: DESCRIPTION,
  },
  // Smart App Banner in Safari on iPhone, once the app is live
  ...(APP_STORE_ID ? { itunes: { appId: APP_STORE_ID } } : {}),
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en">
      <body className="font-sans antialiased">
        {children}
        <Analytics />
        <AnalyticsProvider />
      </body>
    </html>
  )
}
