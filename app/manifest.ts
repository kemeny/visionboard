import type { MetadataRoute } from 'next'

// Lets the app be added to the home screen, which iOS requires for notifications
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Vision Board',
    short_name: 'Vision Board',
    description: 'See your goals. Build your life.',
    start_url: '/',
    display: 'standalone',
    background_color: '#f5f0e8',
    theme_color: '#f5f0e8',
    icons: [
      { src: '/icon.png', sizes: 'any', type: 'image/png' },
      { src: '/apple-icon.png', sizes: '180x180', type: 'image/png' },
    ],
  }
}
