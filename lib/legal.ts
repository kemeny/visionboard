import { headers } from 'next/headers'

// Copy for the Privacy, Terms and Support pages, in English and Spanish.
// App Store Connect links to these pages, and so does the iOS app.

export type Lang = 'en' | 'es'

// Confirm this inbox exists before submitting to the App Store
export const SUPPORT_EMAIL = process.env.NEXT_PUBLIC_SUPPORT_EMAIL || 'support@kemenystudio.com'
export const UPDATED = '2026-11-18'

export interface LegalSection {
  heading: string
  body: string[]
}

export interface LegalDoc {
  title: string
  intro: string
  sections: LegalSection[]
}

// ?lang=es or ?lang=en wins; otherwise the browser's language
export async function pickLang(param: string | string[] | undefined): Promise<Lang> {
  const asked = Array.isArray(param) ? param[0] : param
  if (asked === 'es' || asked === 'en') return asked
  const accept = (await headers()).get('accept-language') ?? ''
  return /^\s*es\b/i.test(accept) ? 'es' : 'en'
}

export const UI: Record<Lang, { updated: string; back: string; other: string; otherLang: Lang; nav: { privacy: string; terms: string; support: string } }> = {
  en: {
    updated: 'Last updated',
    back: 'Back to VisionBoard',
    other: 'Español',
    otherLang: 'es',
    nav: { privacy: 'Privacy', terms: 'Terms', support: 'Support' },
  },
  es: {
    updated: 'Última actualización',
    back: 'Volver a VisionBoard',
    other: 'English',
    otherLang: 'en',
    nav: { privacy: 'Privacidad', terms: 'Términos', support: 'Ayuda' },
  },
}

export const PRIVACY: Record<Lang, LegalDoc> = {
  en: {
    title: 'Privacy Policy',
    intro:
      'VisionBoard is made by Kemeny Studio. This policy explains what the iPhone app and the web app at visionboard.kemenystudio.com collect, why, and how you can control it. You never need an account. Signing in with Apple on iPhone is optional and only used for backup.',
    sections: [
      {
        heading: 'Your board',
        body: [
          'Your goals, photos and board layout stay on your device by default. On the web they live in your browser. On iPhone they live in the app.',
          'If you turn on Sync, a copy of the board and its photos is stored on our servers so your other devices can open it. Board data is kept in a Cloudflare D1 database and photos in Cloudflare R2 storage. The copy is tied to a random sync key, not to your name or email. Anyone with the key or the sync link can open the board, so share it only with people you trust.',
          'Things you share into VisionBoard from other apps are added to your board and handled the same way.',
        ],
      },
      {
        heading: 'Optional account',
        body: [
          'On iPhone you can sign in with Apple to back up your boards. We then store the stable user ID Apple gives us for VisionBoard, the email Apple shares (if you choose to share it, often a private relay address), and the list of your boards: each board\'s name and sync key. That list is encrypted on our servers. Signing in also turns on Sync for every board.',
          'We use this only to bring your boards back on a new device. We never email you for marketing.',
          'To delete it, go to Settings > Account > Delete Account in the app. This deletes the account and the backed-up list, and can also delete the cloud copy of every board. You can also stop using Sign in with Apple for VisionBoard in your iPhone\'s Apple Account settings.',
        ],
      },
      {
        heading: 'Reminders',
        body: [
          'On iPhone, daily reminders are local notifications scheduled on your device. Nothing is sent to us for them.',
          'On the web, reminders use web push. We store your browser\'s push subscription, the reminder time and time zone, and the sync key of the board, so we can send the reminder. Turning reminders off deletes the subscription.',
        ],
      },
      {
        heading: 'Purchases',
        body: [
          'VisionBoard Pro is sold through the App Store. Apple processes the payment. We never see your card or billing details. The app only learns from Apple whether your subscription is active.',
        ],
      },
      {
        heading: 'AI board generation (optional)',
        body: [
          'If you ask the app to make a board for you, the text you type is sent to Anthropic (anthropic.com) to write short phrases for the board, and search words are sent to Unsplash (unsplash.com) to find photos. We send only that text, not your other goals or photos.',
          'This feature runs only when you use it.',
        ],
      },
      {
        heading: 'Anonymous usage analytics',
        body: [
          'We use PostHog (posthog.com) to understand which features people use. It receives an anonymous random ID made on your device, the taps and counts of what you do (for example "a photo was added" or "the board has 12 items"), the app version, the OS version and your language setting.',
          'Analytics never include your goal text, your photos, board names or your sync key. We do not build a profile of you, we do not sell data and we do not use it for advertising or tracking across other apps or websites.',
          'To turn it off on iPhone, go to Settings > Share Anonymous Usage in VisionBoard. On the web, turn on Do Not Track in your browser.',
        ],
      },
      {
        heading: 'Deleting your data',
        body: [
          'To delete the cloud copy of a board and its photos, open Sync (Settings on iPhone) and choose Delete Cloud Copy. This removes it for every device. The board stays on the device you used.',
          'If you signed in with Apple, Delete Account in Settings > Account removes your account data. Deleting the app or clearing your browser data removes everything stored on that device. You can also email us to delete any data tied to a sync key or account.',
        ],
      },
      {
        heading: 'Children',
        body: ['VisionBoard is not directed to children under 13 and we do not knowingly collect their data.'],
      },
      {
        heading: 'Changes and contact',
        body: [
          'If this policy changes we will update this page and the date below.',
          `Questions or requests: ${SUPPORT_EMAIL}.`,
        ],
      },
    ],
  },
  es: {
    title: 'Política de privacidad',
    intro:
      'VisionBoard es un producto de Kemeny Studio. Esta política explica qué datos recogen la app de iPhone y la app web en visionboard.kemenystudio.com, para qué, y cómo puedes controlarlos. Nunca necesitas una cuenta. Iniciar sesión con Apple en iPhone es opcional y solo sirve para respaldar.',
    sections: [
      {
        heading: 'Tu tablero',
        body: [
          'Tus metas, fotos y el diseño del tablero se guardan en tu dispositivo. En la web viven en tu navegador. En iPhone viven en la app.',
          'Si activas la sincronización, una copia del tablero y sus fotos se guarda en nuestros servidores para que tus otros dispositivos puedan abrirlo. Los datos del tablero se guardan en una base de datos Cloudflare D1 y las fotos en Cloudflare R2. La copia está ligada a una clave de sincronización aleatoria, no a tu nombre ni a tu correo. Cualquiera con la clave o el enlace puede abrir el tablero, así que compártelo solo con personas de confianza.',
          'Lo que compartes en VisionBoard desde otras apps se agrega a tu tablero y se trata igual.',
        ],
      },
      {
        heading: 'Cuenta opcional',
        body: [
          'En iPhone puedes iniciar sesión con Apple para respaldar tus tableros. En ese caso guardamos el ID de usuario que Apple nos da para VisionBoard, el correo que Apple comparte (si eliges compartirlo, muchas veces una dirección privada de reenvío) y la lista de tus tableros: el nombre y la clave de sincronización de cada uno. Esa lista se guarda cifrada en nuestros servidores. Al iniciar sesión también se activa la sincronización de todos tus tableros.',
          'Solo usamos esto para recuperar tus tableros en un dispositivo nuevo. Nunca te enviamos correos de marketing.',
          'Para borrarla, ve a Ajustes > Cuenta > Borrar cuenta en la app. Se borran la cuenta y la lista respaldada, y también puedes borrar la copia en la nube de cada tablero. Además puedes dejar de usar Iniciar sesión con Apple para VisionBoard en los ajustes de tu cuenta de Apple en el iPhone.',
        ],
      },
      {
        heading: 'Recordatorios',
        body: [
          'En iPhone, los recordatorios diarios son notificaciones locales programadas en tu dispositivo. No nos llega nada por ellos.',
          'En la web, los recordatorios usan notificaciones push. Guardamos la suscripción push de tu navegador, la hora y zona horaria del recordatorio y la clave del tablero, para poder enviarlo. Al apagar los recordatorios se borra la suscripción.',
        ],
      },
      {
        heading: 'Compras',
        body: [
          'VisionBoard Pro se vende en el App Store. Apple procesa el pago. Nunca vemos tu tarjeta ni tus datos de cobro. La app solo sabe por Apple si tu suscripción está activa.',
        ],
      },
      {
        heading: 'Tableros creados con IA (opcional)',
        body: [
          'Si le pides a la app que cree un tablero por ti, el texto que escribes se envía a Anthropic (anthropic.com) para escribir frases cortas, y las palabras de búsqueda se envían a Unsplash (unsplash.com) para encontrar fotos. Solo enviamos ese texto, no tus otras metas ni tus fotos.',
          'Esta función solo se usa cuando tú la pides.',
        ],
      },
      {
        heading: 'Uso anónimo',
        body: [
          'Usamos PostHog (posthog.com) para entender qué funciones se usan. Recibe un ID anónimo y aleatorio creado en tu dispositivo, los toques y conteos de lo que haces (por ejemplo "se agregó una foto" o "el tablero tiene 12 elementos"), la versión de la app, la versión del sistema y tu idioma.',
          'Nunca se envían el texto de tus metas, tus fotos, los nombres de tus tableros ni tu clave de sincronización. No armamos un perfil tuyo, no vendemos datos y no los usamos para publicidad ni para rastrearte en otras apps o sitios.',
          'Para apagarlo en iPhone, ve a Ajustes > Compartir uso anónimo en VisionBoard. En la web, activa No rastrear (Do Not Track) en tu navegador.',
        ],
      },
      {
        heading: 'Borrar tus datos',
        body: [
          'Para borrar la copia en la nube de un tablero y sus fotos, abre Sincronización (en Ajustes, en iPhone) y elige Eliminar copia en la nube. Se borra para todos los dispositivos. El tablero se queda en el dispositivo que usaste.',
          'Si iniciaste sesión con Apple, Borrar cuenta en Ajustes > Cuenta borra los datos de tu cuenta. Al borrar la app o los datos de tu navegador se borra todo lo guardado en ese dispositivo. También puedes escribirnos para borrar cualquier dato ligado a una clave o a una cuenta.',
        ],
      },
      {
        heading: 'Menores',
        body: ['VisionBoard no está dirigido a menores de 13 años y no recogemos sus datos a sabiendas.'],
      },
      {
        heading: 'Cambios y contacto',
        body: [
          'Si esta política cambia, actualizaremos esta página y la fecha de abajo.',
          `Dudas o solicitudes: ${SUPPORT_EMAIL}.`,
        ],
      },
    ],
  },
}

export const TERMS: Record<Lang, LegalDoc> = {
  en: {
    title: 'Terms of Use',
    intro: 'These terms cover your use of VisionBoard, made by Kemeny Studio, on iPhone and on the web.',
    sections: [
      {
        heading: 'The app',
        body: [
          'The iPhone app is licensed to you under Apple\'s standard Licensed Application End User License Agreement (apple.com/legal/internet-services/itunes/dev/stdeula).',
          'The web app is free to use. We may change or stop features at any time.',
        ],
      },
      {
        heading: 'Subscriptions',
        body: [
          'VisionBoard Pro, when offered, is an auto-renewing subscription billed through your Apple ID. A free trial, if offered, turns into a paid subscription at its end unless you cancel at least 24 hours before. Manage or cancel it in your iPhone Settings under your Apple ID > Subscriptions.',
        ],
      },
      {
        heading: 'Your content',
        body: [
          'What you put on your board is yours. Only add photos and text you have the right to use. You are responsible for who you share a sync key or link with.',
          'Do not use VisionBoard to store or share anything illegal or harmful. We may remove cloud copies that break these terms.',
        ],
      },
      {
        heading: 'No warranty',
        body: [
          'VisionBoard is provided as is. Keep a backup of anything important: use Export on the web. To the extent the law allows, Kemeny Studio is not liable for lost data or indirect damages.',
        ],
      },
      {
        heading: 'Contact',
        body: [`Questions about these terms: ${SUPPORT_EMAIL}.`],
      },
    ],
  },
  es: {
    title: 'Términos de uso',
    intro: 'Estos términos cubren el uso de VisionBoard, de Kemeny Studio, en iPhone y en la web.',
    sections: [
      {
        heading: 'La app',
        body: [
          'La app de iPhone se licencia bajo el Contrato de Licencia de Usuario Final estándar de Apple (apple.com/legal/internet-services/itunes/dev/stdeula).',
          'La app web es gratis. Podemos cambiar o retirar funciones en cualquier momento.',
        ],
      },
      {
        heading: 'Suscripciones',
        body: [
          'VisionBoard Pro, cuando esté disponible, es una suscripción con renovación automática cobrada a tu Apple ID. Si hay una prueba gratis, al terminar pasa a ser una suscripción pagada salvo que canceles al menos 24 horas antes. Puedes administrarla o cancelarla en Ajustes del iPhone, en tu Apple ID > Suscripciones.',
        ],
      },
      {
        heading: 'Tu contenido',
        body: [
          'Lo que pones en tu tablero es tuyo. Agrega solo fotos y textos que tengas derecho a usar. Tú decides con quién compartes una clave o enlace de sincronización.',
          'No uses VisionBoard para guardar o compartir nada ilegal o dañino. Podemos borrar copias en la nube que no cumplan estos términos.',
        ],
      },
      {
        heading: 'Sin garantía',
        body: [
          'VisionBoard se ofrece tal cual. Guarda un respaldo de lo importante: usa Exportar en la web. En la medida que la ley lo permita, Kemeny Studio no responde por datos perdidos ni daños indirectos.',
        ],
      },
      {
        heading: 'Contacto',
        body: [`Dudas sobre estos términos: ${SUPPORT_EMAIL}.`],
      },
    ],
  },
}

export const SUPPORT: Record<Lang, LegalDoc> = {
  en: {
    title: 'Support',
    intro: `Need help with VisionBoard? Email ${SUPPORT_EMAIL} and we will get back to you, usually within two business days.`,
    sections: [
      {
        heading: 'Open my board on another device',
        body: [
          'Turn on Sync, then scan the QR code or open the sync link on the other device. On iPhone it is in Settings. On the web it is the Sync button.',
        ],
      },
      {
        heading: 'Reminders don\'t arrive',
        body: [
          'On iPhone, check that notifications are on for VisionBoard in the Settings app, then use Send a Test in VisionBoard\'s Settings. On the web, allow notifications for this site in your browser.',
        ],
      },
      {
        heading: 'Delete my data',
        body: [
          'Use Delete Cloud Copy in Sync to remove a board and its photos from our servers. Deleting the app removes everything on the device. See the Privacy Policy for details.',
        ],
      },
      {
        heading: 'Subscriptions',
        body: [
          'Subscriptions are billed by Apple. To cancel or ask for a refund, go to your iPhone Settings > your Apple ID > Subscriptions, or reportaproblem.apple.com.',
        ],
      },
    ],
  },
  es: {
    title: 'Ayuda',
    intro: `¿Necesitas ayuda con VisionBoard? Escríbenos a ${SUPPORT_EMAIL} y te respondemos, normalmente en dos días hábiles.`,
    sections: [
      {
        heading: 'Abrir mi tablero en otro dispositivo',
        body: [
          'Activa la sincronización y escanea el código QR o abre el enlace en el otro dispositivo. En iPhone está en Ajustes. En la web es el botón Sync.',
        ],
      },
      {
        heading: 'No me llegan los recordatorios',
        body: [
          'En iPhone, revisa que las notificaciones de VisionBoard estén activas en la app Ajustes y usa Enviar una prueba en los Ajustes de VisionBoard. En la web, permite las notificaciones de este sitio en tu navegador.',
        ],
      },
      {
        heading: 'Borrar mis datos',
        body: [
          'Usa Eliminar copia en la nube, en Sincronización, para quitar un tablero y sus fotos de nuestros servidores. Al borrar la app se borra todo lo del dispositivo. Más detalles en la Política de privacidad.',
        ],
      },
      {
        heading: 'Suscripciones',
        body: [
          'Apple cobra las suscripciones. Para cancelar o pedir un reembolso, ve a Ajustes del iPhone > tu Apple ID > Suscripciones, o a reportaproblem.apple.com.',
        ],
      },
    ],
  },
}
