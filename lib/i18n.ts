'use client'

import { useCallback, useEffect, useSyncExternalStore } from 'react'

// Tiny dictionary i18n for the web app (English and Spanish).
// Language: ?lang=es|en in the address, else the saved choice ('vb-lang'),
// else the browser language (es* -> Spanish), else English.
// The server always renders English; the client switches after hydration.

export type Lang = 'en' | 'es'

const STORAGE_KEY = 'vb-lang'

const en = {
  // Toolbar
  'toolbar.dots': 'Dots',
  'toolbar.grid': 'Grid',
  'toolbar.blank': 'Blank',
  'toolbar.canvasColor': 'Canvas color',
  'toolbar.zoomOut': 'Zoom out',
  'toolbar.resetZoom': 'Reset zoom',
  'toolbar.zoomIn': 'Zoom in',
  'toolbar.feed': 'Feed',
  'toolbar.fitAll': 'Fit all',
  'toolbar.add': 'Add',
  'toolbar.text': 'Text',
  'toolbar.image': 'Image',
  'toolbar.menu': 'Board menu',
  'canvas.moleskine': 'Moleskine',
  'canvas.cream': 'Cream',
  'canvas.gray': 'Gray',
  'canvas.stone': 'Stone',
  'canvas.white': 'White',

  // Board menu
  'menu.sync': 'Sync & reminders',
  'menu.export': 'Export board',
  'menu.import': 'Import board',
  'menu.reset': 'Reset board',
  'menu.resetConfirm': "Clear the whole board? This can't be undone. Export a backup first if you want to keep it.",
  'menu.language': 'Language',
  'menu.getApp': 'Get the iPhone app',
  'menu.shareImage': 'Share as image',
  'share.mark': 'Made with VisionBoard',
  'legal.privacy': 'Privacy',
  'legal.terms': 'Terms',
  'legal.support': 'Support',

  // New clippings
  'item.newText': 'Click to style, triple-click to edit',

  // Welcome overlay
  'welcome.title': 'What do you want in 2027?',
  'welcome.subtitle': 'Write three things. We turn them into your vision board.',
  'welcome.goalsLabel': 'Write 3 things you want in 2027',
  'welcome.goal1': 'Run a half marathon',
  'welcome.goal2': 'Travel to Japan',
  'welcome.goal3': 'Read 20 books',
  'welcome.goalAria': 'Goal {n}',
  'welcome.make': 'Make my board',
  'welcome.orExample': 'Or start from an example',
  'welcome.dropImage': 'Drop an image',
  'welcome.addWords': 'Add words',
  'welcome.openOther': 'Open my board from another device',
  'welcome.hint': 'Paste from clipboard · Drag files onto the canvas',
  'welcome.getApp': 'Get the iPhone app',

  // Selection toolbars
  'sel.reset': 'Reset',
  'sel.lock': 'Lock',
  'sel.unlock': 'Unlock',
  'sel.lockAll': 'Lock all',
  'sel.unlockAll': 'Unlock all',
  'sel.front': 'Bring to front',
  'sel.back': 'Send to back',
  'sel.delete': 'Delete',
  'sel.bgColor': 'Background color',
  'sel.count': '{n} selected',
  'sel.alignLeft': 'Align left',
  'sel.alignCenter': 'Align center',
  'sel.alignRight': 'Align right',
  'sel.alignTop': 'Align top',
  'sel.alignMiddle': 'Align middle',
  'sel.alignBottom': 'Align bottom',
  'sel.distH': 'Distribute horizontally',
  'sel.distV': 'Distribute vertically',
  'sel.collage': 'Arrange as collage',
  'sel.removeBg': 'Remove BG',
  'sel.removingBg': 'Removing…',
  'sel.restoreBg': 'Restore BG',
  'sel.resetRotation': 'Reset rotation',

  // Backup reminder
  'backup.text': 'Your board is saved only in this browser. Keep a backup file.',
  'backup.sync': 'Sync',
  'backup.backUp': 'Back up',
  'backup.later': 'Later',

  // Feed
  'feed.aria': 'Feed',
  'feed.back': 'Back to board',
  'feed.forYou': 'For you',
  'feed.liked': 'Liked',
  'feed.emptyLiked': 'Nothing liked yet',
  'feed.emptyBoard': 'Your board is empty',
  'feed.emptyLikedBody': "Double-tap clippings you love in For you, and they'll collect here.",
  'feed.emptyBoardBody': 'Add photos and words to your board to fill your feed.',
  'feed.like': 'Like',
  'feed.unlike': 'Unlike',

  // Today card
  'today.aria': "Today's reminder",
  'today.close': 'Close',
  'today.label': 'Today',
  'today.tap': 'Tap to see your board',

  // Sync dialog
  'sync.title': 'Sync & reminders',
  'sync.description': 'Keep your board safe in the cloud, open it on any device, and get a daily nudge.',
  'sync.unavailable': "Sync isn't set up on this site yet.",
  'sync.cloud': 'Cloud sync',
  'sync.saving': 'Saving…',
  'sync.notSaved': 'Not fully saved',
  'sync.saved': 'Saved',
  'sync.qrAlt': 'QR code that opens this board',
  'sync.openOther': 'Open on another device',
  'sync.scan': "Scan with your phone's camera, or send the link.",
  'sync.private': 'Anyone with the link can see and edit your board, so keep it to yourself.',
  'sync.linkCopied': 'Link copied',
  'sync.sendLink': 'Send link',
  'sync.copyKey': 'Copy key',
  'sync.stop': 'Stop syncing this device',
  'sync.delete': 'Delete cloud copy',
  'sync.deleteConfirm': 'Delete the cloud copy for every device? The board stays on this device.',
  'sync.already': 'Already synced on another device?',
  'sync.alreadyBody': 'Scan the QR code shown there, open the link you sent yourself, or paste the key.',
  'sync.paste': 'Paste',
  'sync.open': 'Open',
  'sync.start': 'Start syncing the board on this device',
  'sync.reminder': 'Daily reminder',
  'sync.iosStep1': 'Tap Share in Safari, then "Add to Home Screen".',
  'sync.iosStep2': 'Open VisionBoard from your Home Screen.',
  'sync.iosStep3': 'Paste your key there and turn on the reminder.',
  'sync.noPush': "This browser doesn't support notifications.",
  'sync.reminderBody': 'One notification a day with something from your board. Turning this on also turns on sync.',
  'sync.sendTest': 'Send a test',
  'sync.testSent': 'Test sent. It should arrive in a few seconds.',
  'sync.shareTitle': 'My vision board',
  'sync.generic': 'Something went wrong',
  'sync.iosAfterJoin':
    'Board opened. For daily reminders: tap Copy key below, then Share and "Add to Home Screen", open it from there and tap Paste.',
  'sync.alreadyOpen': 'This board is already open on this device.',
  'sync.replaceConfirm': "Open your synced board here? It replaces what's on this device.",
  'sync.clipboardError': "Couldn't read the clipboard. Long-press the box and choose Paste.",
}

export type MessageKey = keyof typeof en

const es: Record<MessageKey, string> = {
  'toolbar.dots': 'Puntos',
  'toolbar.grid': 'Cuadrícula',
  'toolbar.blank': 'Liso',
  'toolbar.canvasColor': 'Color del fondo',
  'toolbar.zoomOut': 'Alejar',
  'toolbar.resetZoom': 'Restablecer zoom',
  'toolbar.zoomIn': 'Acercar',
  'toolbar.feed': 'Feed',
  'toolbar.fitAll': 'Ver todo',
  'toolbar.add': 'Agregar',
  'toolbar.text': 'Texto',
  'toolbar.image': 'Imagen',
  'toolbar.menu': 'Menú del tablero',
  'canvas.moleskine': 'Moleskine',
  'canvas.cream': 'Crema',
  'canvas.gray': 'Gris',
  'canvas.stone': 'Piedra',
  'canvas.white': 'Blanco',

  'menu.sync': 'Sincronización y recordatorios',
  'menu.export': 'Exportar tablero',
  'menu.import': 'Importar tablero',
  'menu.reset': 'Vaciar tablero',
  'menu.resetConfirm': '¿Vaciar todo el tablero? No se puede deshacer. Exporta una copia antes si quieres guardarlo.',
  'menu.language': 'Idioma',
  'menu.getApp': 'Descarga la app para iPhone',
  'menu.shareImage': 'Compartir como imagen',
  'share.mark': 'Hecho con VisionBoard',
  'legal.privacy': 'Privacidad',
  'legal.terms': 'Términos',
  'legal.support': 'Ayuda',

  'item.newText': 'Toca para dar estilo, triple toque para editar',

  'welcome.title': '¿Qué quieres para 2027?',
  'welcome.subtitle': 'Escribe tres cosas. Las convertimos en tu tablero de visión.',
  'welcome.goalsLabel': 'Escribe 3 cosas que quieres en 2027',
  'welcome.goal1': 'Correr una media maratón',
  'welcome.goal2': 'Viajar a Japón',
  'welcome.goal3': 'Leer 20 libros',
  'welcome.goalAria': 'Meta {n}',
  'welcome.make': 'Crear mi tablero',
  'welcome.orExample': 'O empieza con un ejemplo',
  'welcome.dropImage': 'Subir una imagen',
  'welcome.addWords': 'Agregar palabras',
  'welcome.openOther': 'Abrir mi tablero desde otro dispositivo',
  'welcome.hint': 'Pega desde el portapapeles · Arrastra archivos al tablero',
  'welcome.getApp': 'Descarga la app para iPhone',

  'sel.reset': 'Restablecer',
  'sel.lock': 'Bloquear',
  'sel.unlock': 'Desbloquear',
  'sel.lockAll': 'Bloquear todo',
  'sel.unlockAll': 'Desbloquear todo',
  'sel.front': 'Traer al frente',
  'sel.back': 'Enviar al fondo',
  'sel.delete': 'Eliminar',
  'sel.bgColor': 'Color de fondo',
  'sel.count': '{n} seleccionados',
  'sel.alignLeft': 'Alinear a la izquierda',
  'sel.alignCenter': 'Centrar',
  'sel.alignRight': 'Alinear a la derecha',
  'sel.alignTop': 'Alinear arriba',
  'sel.alignMiddle': 'Alinear al medio',
  'sel.alignBottom': 'Alinear abajo',
  'sel.distH': 'Distribuir en horizontal',
  'sel.distV': 'Distribuir en vertical',
  'sel.collage': 'Ordenar como collage',
  'sel.removeBg': 'Quitar fondo',
  'sel.removingBg': 'Quitando…',
  'sel.restoreBg': 'Recuperar fondo',
  'sel.resetRotation': 'Quitar giro',

  'backup.text': 'Tu tablero se guarda solo en este navegador. Guarda una copia.',
  'backup.sync': 'Sincronizar',
  'backup.backUp': 'Guardar copia',
  'backup.later': 'Después',

  'feed.aria': 'Feed',
  'feed.back': 'Volver al tablero',
  'feed.forYou': 'Para ti',
  'feed.liked': 'Me gusta',
  'feed.emptyLiked': 'Aún no hay favoritos',
  'feed.emptyBoard': 'Tu tablero está vacío',
  'feed.emptyLikedBody': 'Toca dos veces lo que te encante en Para ti y aparecerá aquí.',
  'feed.emptyBoardBody': 'Agrega fotos y palabras a tu tablero para llenar tu feed.',
  'feed.like': 'Me gusta',
  'feed.unlike': 'Ya no me gusta',

  'today.aria': 'Recordatorio de hoy',
  'today.close': 'Cerrar',
  'today.label': 'Hoy',
  'today.tap': 'Toca para ver tu tablero',

  'sync.title': 'Sincronización y recordatorios',
  'sync.description': 'Guarda tu tablero en la nube, ábrelo en cualquier dispositivo y recibe un recordatorio diario.',
  'sync.unavailable': 'La sincronización aún no está disponible en este sitio.',
  'sync.cloud': 'Sincronización en la nube',
  'sync.saving': 'Guardando…',
  'sync.notSaved': 'No se guardó todo',
  'sync.saved': 'Guardado',
  'sync.qrAlt': 'Código QR que abre este tablero',
  'sync.openOther': 'Abrir en otro dispositivo',
  'sync.scan': 'Escanéalo con la cámara de tu teléfono o envía el enlace.',
  'sync.private': 'Cualquiera con el enlace puede ver y editar tu tablero. Guárdalo para ti.',
  'sync.linkCopied': 'Enlace copiado',
  'sync.sendLink': 'Enviar enlace',
  'sync.copyKey': 'Copiar clave',
  'sync.stop': 'Dejar de sincronizar este dispositivo',
  'sync.delete': 'Eliminar copia en la nube',
  'sync.deleteConfirm': '¿Eliminar la copia en la nube para todos los dispositivos? El tablero se queda en este dispositivo.',
  'sync.already': '¿Ya sincronizas en otro dispositivo?',
  'sync.alreadyBody': 'Escanea el código QR que aparece allá, abre el enlace que te enviaste o pega la clave.',
  'sync.paste': 'Pegar',
  'sync.open': 'Abrir',
  'sync.start': 'Sincronizar el tablero en este dispositivo',
  'sync.reminder': 'Recordatorio diario',
  'sync.iosStep1': 'En Safari, toca Compartir y luego "Agregar a inicio".',
  'sync.iosStep2': 'Abre VisionBoard desde tu pantalla de inicio.',
  'sync.iosStep3': 'Pega tu clave ahí y activa el recordatorio.',
  'sync.noPush': 'Este navegador no admite notificaciones.',
  'sync.reminderBody': 'Una notificación al día con algo de tu tablero. Al activarlo también se activa la sincronización.',
  'sync.sendTest': 'Enviar una prueba',
  'sync.testSent': 'Prueba enviada. Debería llegar en unos segundos.',
  'sync.shareTitle': 'Mi tablero de visión',
  'sync.generic': 'Algo salió mal',
  'sync.iosAfterJoin':
    'Tablero abierto. Para los recordatorios diarios: toca Copiar clave abajo, luego Compartir y "Agregar a inicio", ábrelo desde ahí y toca Pegar.',
  'sync.alreadyOpen': 'Este tablero ya está abierto en este dispositivo.',
  'sync.replaceConfirm': '¿Abrir aquí tu tablero sincronizado? Reemplaza lo que hay en este dispositivo.',
  'sync.clipboardError': 'No se pudo leer el portapapeles. Mantén presionado el campo y elige Pegar.',
}

const DICTS: Record<Lang, Record<MessageKey, string>> = { en, es }

export function translate(lang: Lang, key: MessageKey, vars?: Record<string, string | number>): string {
  let s = DICTS[lang][key] ?? en[key] ?? key
  if (vars) for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v))
  return s
}

// Shared store so every component switches together
let current: Lang | null = null
const listeners = new Set<() => void>()

function detect(): Lang {
  try {
    const param = new URLSearchParams(window.location.search).get('lang')
    if (param === 'es' || param === 'en') {
      try { localStorage.setItem(STORAGE_KEY, param) } catch {}
      return param
    }
  } catch {}
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved === 'es' || saved === 'en') return saved
  } catch {}
  const nav = typeof navigator !== 'undefined' ? navigator.language || '' : ''
  return nav.toLowerCase().startsWith('es') ? 'es' : 'en'
}

function getLang(): Lang {
  if (typeof window === 'undefined') return 'en'
  if (current === null) current = detect()
  return current
}

export function setLang(lang: Lang): void {
  current = lang
  try { localStorage.setItem(STORAGE_KEY, lang) } catch {}
  listeners.forEach((l) => l())
}

function subscribe(cb: () => void) {
  listeners.add(cb)
  return () => { listeners.delete(cb) }
}

export function useT() {
  const lang = useSyncExternalStore(subscribe, getLang, () => 'en' as Lang)
  useEffect(() => {
    document.documentElement.lang = lang
  }, [lang])
  const t = useCallback(
    (key: MessageKey, vars?: Record<string, string | number>) => translate(lang, key, vars),
    [lang]
  )
  return { t, lang, setLang }
}
