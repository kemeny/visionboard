import { ImageResponse } from 'next/og'

export const runtime = 'edge'
export const alt = 'Vision Board — See your goals. Build your life.'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          background: '#f5f0e8',
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: 'system-ui, sans-serif',
          position: 'relative',
        }}
      >
        {/* Dot pattern overlay */}
        <div
          style={{
            position: 'absolute',
            inset: 0,
            backgroundImage: 'radial-gradient(circle, rgba(0,0,0,0.08) 1px, transparent 1px)',
            backgroundSize: '24px 24px',
          }}
        />

        {/* Scattered color cards */}
        <div style={{ position: 'absolute', top: 80, left: 100, width: 200, height: 70, background: 'rgba(59,130,246,0.85)', borderRadius: 12, transform: 'rotate(-3deg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ color: 'white', fontSize: 20, fontWeight: 600, letterSpacing: '0.05em', textTransform: 'uppercase' as const }}>Dream big</span>
        </div>
        <div style={{ position: 'absolute', top: 90, right: 120, width: 180, height: 70, background: 'rgba(236,72,153,0.85)', borderRadius: 12, transform: 'rotate(2deg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ color: 'white', fontSize: 20, fontWeight: 600 }}>Take action</span>
        </div>
        <div style={{ position: 'absolute', bottom: 120, left: 140, width: 170, height: 65, background: 'rgba(139,92,246,0.85)', borderRadius: 12, transform: 'rotate(2deg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ color: 'white', fontSize: 18, fontWeight: 600 }}>Stay focused</span>
        </div>
        <div style={{ position: 'absolute', bottom: 110, right: 100, width: 190, height: 65, background: 'rgba(34,197,94,0.85)', borderRadius: 12, transform: 'rotate(-2deg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ color: 'white', fontSize: 18, fontWeight: 600 }}>Keep growing</span>
        </div>

        {/* Center content */}
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16, zIndex: 1 }}>
          <span style={{ fontSize: 72, fontWeight: 900, color: '#1a1a1a', letterSpacing: '-0.03em', textTransform: 'uppercase' as const, lineHeight: 1 }}>
            Vision Board
          </span>
          <span style={{ fontSize: 24, color: '#6b7280', fontWeight: 400 }}>
            See your goals. Build your life.
          </span>
        </div>

        {/* Footer */}
        <div style={{ position: 'absolute', bottom: 30, display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontSize: 14, color: '#9ca3af' }}>kemenystudio.com</span>
        </div>
      </div>
    ),
    { ...size }
  )
}
