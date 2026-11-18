"use client"

import { useState, useRef, useCallback, useEffect } from "react"
import {
  Plus,
  Type,
  ImageIcon,
  Search,
  Trash2,
  RotateCcw,
  Minus as MinusIcon,
  Plus as PlusIcon,
  PaintBucket,
  ArrowUpToLine,
  ArrowDownToLine,
  ZoomIn,
  ZoomOut,
  Maximize,
  AlignStartVertical,
  AlignEndVertical,
  AlignCenterVertical,
  AlignStartHorizontal,
  AlignEndHorizontal,
  AlignCenterHorizontal,
  Eraser,
  Loader2,
  LayoutGrid,
  Download,
  Upload,
  MoreVertical,
  Lock,
  Unlock,
  Sparkles,
  RotateCw,
  Cloud,
  GalleryVerticalEnd,
  Smartphone,
  ArrowRight,
  Share2,
  BadgeCheck,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { cn } from "@/lib/utils"
import { BoardItem, TEXT_COLORS, FONT_SIZES, TEXT_STYLES, FontStyle } from "@/lib/types"
import { daysSinceCreated } from "@/lib/progress"

const LEGACY_STYLE_MAP: Record<string, FontStyle> = {
  normal: 'clean', bold: 'loud', italic: 'editorial', serif: 'elegant',
}
function resolveStyle(fs?: string): FontStyle {
  if (!fs) return 'clean'
  if (LEGACY_STYLE_MAP[fs]) return LEGACY_STYLE_MAP[fs]
  return fs as FontStyle
}
import {
  saveItemsDB,
  loadItemsDB,
  saveMaxZDB,
  loadMaxZDB,
  migrateFromLocalStorage,
  requestPersistentStorage,
  markBackedUp,
  snoozeBackupReminder,
  shouldRemindBackup,
} from "@/lib/storage"
import {
  refreshServiceWorker,
  takePendingReminderUrl,
  takeSyncKeyFromUrl,
  takeTodayFromUrl,
  type TodayCard as TodayCardData,
} from "@/lib/sync"
import { TEMPLATES, localizeTemplate } from "@/lib/templates"
import { track } from "@/lib/analytics"
import { useT, type MessageKey } from "@/lib/i18n"
import { renderBoardStory, shareOrDownloadImage } from "@/lib/share-image"
import { BoardItemComponent } from "./board-item"
import { SyncDialog } from "./sync-dialog"
import { TodayCard } from "./today-card"
import { PhotoCredit } from "./photo-credit"
import { PhotoSearchDialog, type PickedPhoto } from "./photo-search-dialog"
import { FeedView } from "./feed-view"
import { useBoardSync } from "@/hooks/use-board-sync"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"

// Set in Vercel once the app is live; the App Store pill stays hidden until then
const APP_STORE_URL = process.env.NEXT_PUBLIC_APP_STORE_URL || ""

// Looks for the clippings the welcome goals turn into
const GOAL_LOOKS: Pick<BoardItem, "fontStyle" | "bgColor" | "color">[] = [
  { fontStyle: "loud", bgColor: "rgba(0,0,0,0.8)", color: "#ffffff" },
  { fontStyle: "editorial", bgColor: "rgba(59,130,246,0.85)", color: "#ffffff" },
  { fontStyle: "elegant", bgColor: "rgba(236,72,153,0.85)", color: "#ffffff" },
  { fontStyle: "poster", bgColor: "rgba(234,179,8,0.9)", color: "#1a1a1a" },
  { fontStyle: "handwritten", bgColor: "rgba(255,255,255,0.9)", color: "#1a1a1a" },
  { fontStyle: "mono", bgColor: "rgba(139,92,246,0.85)", color: "#ffffff" },
  { fontStyle: "compact", bgColor: "rgba(34,197,94,0.85)", color: "#ffffff" },
]

// Staggered spots for up to three goals, so they read like a collage
const GOAL_SPOTS = [
  { x: 120, y: 100, rotation: -2 },
  { x: 420, y: 270, rotation: 2 },
  { x: 160, y: 450, rotation: -1 },
]

export function VisionBoard() {
  const { t, lang, setLang } = useT()
  const canvasPatternOptions = ['canvas-dots', 'canvas-grid', 'canvas-blank'] as const
  type CanvasPattern = typeof canvasPatternOptions[number]

  const canvasBgColors = [
    { id: 'canvas-bg-warm', label: 'canvas.moleskine', color: '#f5f0e8' },
    { id: 'canvas-bg-cream', label: 'canvas.cream', color: '#faf6ef' },
    { id: 'canvas-bg-gray', label: 'canvas.gray', color: '#f0f0ee' },
    { id: 'canvas-bg-stone', label: 'canvas.stone', color: '#eae6df' },
    { id: 'canvas-bg-white', label: 'canvas.white', color: '#ffffff' },
  ] as const
  type CanvasBgColor = typeof canvasBgColors[number]['id']

  const [items, setItems] = useState<BoardItem[]>([])
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [maxZIndex, setMaxZIndex] = useState(1)
  const [isLoaded, setIsLoaded] = useState(false)
  const [canvasPattern, setCanvasPattern] = useState<CanvasPattern>('canvas-dots')
  const [isRemovingBg, setIsRemovingBg] = useState(false)
  const [canvasBgColor, setCanvasBgColor] = useState<CanvasBgColor>('canvas-bg-warm')
  const [zoom, setZoom] = useState(1)
  // For analytics: how many clippings the board has, without re-creating callbacks
  const itemCountRef = useRef(0)
  itemCountRef.current = items.length
  const [showBackupReminder, setShowBackupReminder] = useState(false)
  const [syncOpen, setSyncOpen] = useState(false)
  const [photoSearchOpen, setPhotoSearchOpen] = useState(false)
  const [linkKey, setLinkKey] = useState<string | null>(null)
  const [todayCard, setTodayCard] = useState<TodayCardData | null>(null)
  const [feedOpen, setFeedOpen] = useState(false)
  const [goals, setGoals] = useState(["", "", ""])
  const goalRefs = useRef<(HTMLInputElement | null)[]>([])
  // True while the empty-board welcome is up, until the first board is made
  const onboardingActive = useRef(false)
  const onboardingSeen = useRef(false)
  const canvasRef = useRef<HTMLDivElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const importInputRef = useRef<HTMLInputElement>(null)

  // Load from IndexedDB + localStorage preferences on mount
  useEffect(() => {
    // Load canvas preferences from localStorage
    const savedPattern = localStorage.getItem('visionboard-canvas-pattern') as CanvasPattern | null
    if (savedPattern && canvasPatternOptions.includes(savedPattern)) {
      setCanvasPattern(savedPattern)
    }
    const savedBgColor = localStorage.getItem('visionboard-canvas-bg-color') as CanvasBgColor | null
    if (savedBgColor) {
      setCanvasBgColor(savedBgColor)
    }

    async function load() {
      try {
        const migrated = await migrateFromLocalStorage()
        if (migrated) {
          setItems(migrated.items)
          setMaxZIndex(migrated.maxZ)
        } else {
          const [savedItems, savedMaxZ] = await Promise.all([
            loadItemsDB(),
            loadMaxZDB(),
          ])
          setItems(savedItems)
          setMaxZIndex(savedMaxZ)
        }
      } catch {
        // DB unavailable, start fresh
      }
      setIsLoaded(true)
    }
    load()
    requestPersistentStorage()
  }, [])

  const applyRemote = useCallback((remoteItems: BoardItem[], remoteMaxZ: number) => {
    setItems(remoteItems)
    setMaxZIndex(remoteMaxZ)
    setSelectedIds(new Set())
    // Zoom to fit the incoming board, e.g. a desktop-sized board opened on a phone
    hasInitialFit.current = false
  }, [])
  const sync = useBoardSync({ items, maxZIndex, isLoaded, applyRemote, replaceItems: setItems })

  // Links into the app: a "Send link"/QR key goes to the sync dialog, and a
  // tapped reminder opens today's card. Handled after the local board has
  // loaded so a joined board can't race it.
  useEffect(() => {
    if (!isLoaded) return
    const check = () => {
      const card = takeTodayFromUrl()
      if (card) {
        setTodayCard(card)
        track("reminder_opened", { kind: "daily" })
        track("today_viewed", { surface: "reminder" })
      }
      const key = takeSyncKeyFromUrl()
      if (!key) return
      setLinkKey(key)
      setSyncOpen(true)
    }
    check()
    // The link may be opened while the app is already open in this tab, which
    // only changes the fragment and doesn't reload the page
    window.addEventListener("hashchange", check)
    // A tapped reminder reaches an already-open app as a service worker
    // message, or, if the app was suspended and missed it, as a parked link
    // Only the fragment matters (its contents are validated when read), so a
    // link saved under another address of this app still opens here
    const openUrl = (raw: string) => {
      const { hash } = new URL(raw, window.location.origin)
      if (hash) window.location.hash = hash
    }
    const onMessage = (e: MessageEvent) => {
      if (e.data?.type !== "open-url") return
      openUrl(e.data.url)
      // This tap was also parked for a suspended app; clear it so it doesn't
      // reopen the card the next time the app comes to the foreground
      takePendingReminderUrl()
    }
    const checkPending = () => {
      if (document.visibilityState !== "visible") return
      takePendingReminderUrl().then((url) => url && openUrl(url))
    }
    navigator.serviceWorker?.addEventListener("message", onMessage)
    document.addEventListener("visibilitychange", checkPending)
    checkPending()
    refreshServiceWorker()
    return () => {
      window.removeEventListener("hashchange", check)
      navigator.serviceWorker?.removeEventListener("message", onMessage)
      document.removeEventListener("visibilitychange", checkPending)
    }
  }, [isLoaded])

  // Nudge toward a backup file, since the board otherwise lives only in this browser
  useEffect(() => {
    if (!isLoaded) return
    setShowBackupReminder(!sync.syncKey && shouldRemindBackup(items.length))
  }, [items.length, isLoaded, sync.syncKey])

  // Save to IndexedDB on change
  useEffect(() => {
    if (!isLoaded) return
    saveItemsDB(items).catch(() => {})
  }, [items, isLoaded])

  useEffect(() => {
    if (!isLoaded) return
    saveMaxZDB(maxZIndex).catch(() => {})
  }, [maxZIndex, isLoaded])

  // Millisecond prefix, like iOS ids, so both apps can tell when an item was added
  const generateId = () => `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`

  // The welcome overlay is onboarding: count it once per visit when it shows
  const showWelcome = isLoaded && items.length === 0
  useEffect(() => {
    if (!showWelcome || onboardingSeen.current) return
    onboardingSeen.current = true
    onboardingActive.current = true
    track("onboarding_started", { surface: "welcome" })
  }, [showWelcome])

  const finishOnboarding = useCallback((path: "goals" | "template" | "blank", goalsCount = 0) => {
    if (!onboardingActive.current) return
    onboardingActive.current = false
    track("onboarding_completed", { path, goals_count: goalsCount })
  }, [])

  const selectedItem = selectedIds.size === 1 ? items.find((i) => selectedIds.has(i.id)) : null
  const selectedItems = items.filter((i) => selectedIds.has(i.id))

  const addTextItem = useCallback(() => {
    const newItem: BoardItem = {
      id: generateId(),
      type: "text",
      x: 100 + Math.random() * 200,
      y: 100 + Math.random() * 200,
      width: 220,
      height: 120,
      content: t("item.newText"),
      zIndex: maxZIndex,
      fontStyle: "clean",
      fontSize: 18,
      color: "#1a1a1a",
      rotation: 0,
    }
    setItems((prev) => [...prev, newItem])
    setMaxZIndex((prev) => prev + 1)
    setSelectedIds(new Set([newItem.id]))
    track("item_added", { source: "text", board_item_count: itemCountRef.current + 1 })
    finishOnboarding("blank")
  }, [maxZIndex, t, finishOnboarding])

  const loadTemplate = useCallback((templateId: string) => {
    const found = TEMPLATES.find((tmpl) => tmpl.id === templateId)
    if (!found) return
    const template = localizeTemplate(found, lang)
    const newItems: BoardItem[] = template.items.map((item, i) => ({
      ...item,
      id: generateId(),
      zIndex: item.zIndex || i + 1,
    }))
    setItems(newItems)
    setMaxZIndex(newItems.length + 1)
    setSelectedIds(new Set())
    setZoom(1)
    // Same meaning as on iOS: blank paper is blank_started, an example is template_loaded
    const surface = onboardingActive.current ? "onboarding" : "board"
    if (templateId === "blank") track("blank_started", { surface })
    else track("template_loaded", { template: templateId, surface })
    finishOnboarding(templateId === "blank" ? "blank" : "template")
  }, [lang, finishOnboarding])

  // Welcome goals: each one becomes a styled text clipping
  const makeGoalsBoard = useCallback(() => {
    const filled = goals.map((g) => g.trim()).filter(Boolean).slice(0, GOAL_SPOTS.length)
    if (filled.length === 0) return
    const looks = [...GOAL_LOOKS]
    for (let i = looks.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [looks[i], looks[j]] = [looks[j], looks[i]]
    }
    const newItems: BoardItem[] = filled.map((content, i) => {
      const spot = GOAL_SPOTS[i]
      const long = content.length > 22
      return {
        id: generateId(),
        type: "text",
        x: spot.x,
        y: spot.y,
        width: long ? 380 : 340,
        height: long ? 150 : 110,
        content,
        zIndex: i + 1,
        fontSize: long ? 24 : 28,
        rotation: spot.rotation,
        ...looks[i],
      }
    })
    setItems(newItems)
    setMaxZIndex(newItems.length + 1)
    setSelectedIds(new Set())
    setZoom(1)
    setGoals(["", "", ""])
    finishOnboarding("goals", filled.length)
  }, [goals, finishOnboarding])

  const resetBoard = useCallback(() => {
    if (!window.confirm(t("menu.resetConfirm"))) return
    setItems([])
    setMaxZIndex(1)
    setSelectedIds(new Set())
    setZoom(1)
    track("board_reset", { surface: "board" })
  }, [t])

  const handleImageUpload = useCallback(
    (file: File, source: "upload" | "drop" | "paste" = "upload") => {
      const reader = new FileReader()
      reader.onload = (e) => {
        const dataUrl = e.target?.result as string
        if (!dataUrl) return

        const newItem: BoardItem = {
          id: generateId(),
          type: "image",
          x: 100 + Math.random() * 200,
          y: 100 + Math.random() * 200,
          width: 300,
          height: 200,
          content: dataUrl,
          zIndex: maxZIndex,
          rotation: 0,
        }
        setItems((prev) => [...prev, newItem])
        setMaxZIndex((prev) => prev + 1)
        setSelectedIds(new Set([newItem.id]))
        track("item_added", { source, board_item_count: itemCountRef.current + 1 })
        finishOnboarding("blank")
      }
      reader.readAsDataURL(file)
    },
    [maxZIndex, finishOnboarding]
  )

  // Unsplash photos from Search photos: hotlinked, with the photographer's credit
  const addSearchPhotos = useCallback(
    (photos: PickedPhoto[]) => {
      if (!photos.length) return
      const baseX = 100 + Math.random() * 200
      const baseY = 100 + Math.random() * 200
      const newItems: BoardItem[] = photos.map((photo, i) => {
        const width = 300
        return {
          id: generateId(),
          type: "image",
          x: baseX + i * 30,
          y: baseY + i * 30,
          width,
          height: Math.round(width / Math.max(photo.aspect, 0.1)),
          content: photo.imageUrl,
          zIndex: maxZIndex + i,
          rotation: 0,
          ...(photo.credit && { credit: photo.credit }),
        }
      })
      setItems((prev) => [...prev, ...newItems])
      setMaxZIndex((prev) => prev + newItems.length)
      setSelectedIds(new Set([newItems[newItems.length - 1].id]))
      newItems.forEach((_, i) =>
        track("item_added", { source: "photo_search", board_item_count: itemCountRef.current + i + 1 })
      )
      finishOnboarding("blank")
    },
    [maxZIndex, finishOnboarding]
  )

  const handleFileSelect = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0]
      if (file) {
        handleImageUpload(file)
      }
      e.target.value = ""
    },
    [handleImageUpload]
  )

  // Handle paste for images
  useEffect(() => {
    const handlePaste = (e: ClipboardEvent) => {
      const clipItems = e.clipboardData?.items
      if (!clipItems) return

      for (const clipItem of Array.from(clipItems)) {
        if (clipItem.type.startsWith("image/")) {
          const file = clipItem.getAsFile()
          if (file) {
            handleImageUpload(file, "paste")
          }
          break
        }
      }
    }

    window.addEventListener("paste", handlePaste)
    return () => window.removeEventListener("paste", handlePaste)
  }, [handleImageUpload])

  const updateItem = useCallback((id: string, updates: Partial<BoardItem>) => {
    setItems((prev) =>
      prev.map((item) => (item.id === id ? { ...item, ...updates } : item))
    )
  }, [])

  // On phones the app reopens in whichever view you left it in
  const openFeed = useCallback((open: boolean) => {
    setFeedOpen(open)
    if (open) track("feed_viewed", { board_item_count: itemCountRef.current })
    try {
      localStorage.setItem("visionboard-view", open ? "feed" : "board")
    } catch {}
  }, [])

  useEffect(() => {
    if (!isLoaded || items.length === 0) return
    try {
      if (window.matchMedia("(max-width: 640px)").matches && localStorage.getItem("visionboard-view") === "feed") {
        setFeedOpen(true)
        track("feed_viewed", { board_item_count: items.length })
      }
    } catch {}
    // Only decide once the board has loaded
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isLoaded])

  const deleteItem = useCallback((id: string) => {
    setItems((prev) => prev.filter((item) => item.id !== id))
  }, [])

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const active = document.activeElement
      if (active instanceof HTMLTextAreaElement || active instanceof HTMLInputElement) return

      // ⌘+A / Ctrl+A: select all
      if ((e.metaKey || e.ctrlKey) && e.key === "a") {
        e.preventDefault()
        setSelectedIds(new Set(items.map((i) => i.id)))
        return
      }

      if (selectedIds.size === 0) return

      if (e.key === "Delete" || e.key === "Backspace") {
        e.preventDefault()
        selectedIds.forEach((id) => deleteItem(id))
        setSelectedIds(new Set())
      }
    }

    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [selectedIds, deleteItem, items])

  const bringToFront = useCallback(
    (id: string) => {
      setItems((prev) =>
        prev.map((item) =>
          item.id === id ? { ...item, zIndex: maxZIndex } : item
        )
      )
      setMaxZIndex((prev) => prev + 1)
    },
    [maxZIndex]
  )

  const sendToBack = useCallback(
    (id: string) => {
      setItems((prev) => {
        const minZ = Math.min(...prev.map((item) => item.zIndex))
        return prev.map((item) =>
          item.id === id ? { ...item, zIndex: minZ - 1 } : item
        )
      })
    },
    []
  )

  const handleCanvasClick = useCallback((e: React.MouseEvent) => {
    const target = e.target as HTMLElement
    if (target === e.currentTarget || target.dataset.canvas === "true") {
      setSelectedIds(new Set())
    }
  }, [])

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault()
      const files = Array.from(e.dataTransfer.files)
      const imageFile = files.find((f) => f.type.startsWith("image/"))
      if (imageFile) {
        handleImageUpload(imageFile, "drop")
      }
    },
    [handleImageUpload]
  )

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
  }, [])

  const fitAll = useCallback(() => {
    if (items.length === 0 || !canvasRef.current) return
    const padding = 60
    const minX = Math.min(...items.map((i) => i.x))
    const minY = Math.min(...items.map((i) => i.y))
    const maxX = Math.max(...items.map((i) => i.x + i.width))
    const maxY = Math.max(...items.map((i) => i.y + i.height))
    const contentW = maxX - minX + padding * 2
    const contentH = maxY - minY + padding * 2
    const viewW = canvasRef.current.clientWidth
    const viewH = canvasRef.current.clientHeight
    const scale = Math.min(viewW / contentW, viewH / contentH, 1)
    setZoom(Math.round(scale * 100) / 100)
    // After zoom updates, scroll to center the content
    requestAnimationFrame(() => {
      if (!canvasRef.current) return
      const scrollX = (minX - padding) * scale - (viewW - contentW * scale) / 2
      const scrollY = (minY - padding) * scale - (viewH - contentH * scale) / 2
      canvasRef.current.scrollTo({ left: Math.max(0, scrollX), top: Math.max(0, scrollY), behavior: 'smooth' })
    })
  }, [items])

  // Fit all on initial load
  const hasInitialFit = useRef(false)
  useEffect(() => {
    if (!isLoaded || hasInitialFit.current || items.length === 0) return
    hasInitialFit.current = true
    requestAnimationFrame(() => fitAll())
  }, [isLoaded, items, fitAll])

  const zoomIn = useCallback(() => {
    setZoom((z) => Math.min(2, Math.round((z + 0.1) * 100) / 100))
  }, [])

  const zoomOut = useCallback(() => {
    setZoom((z) => Math.max(0.1, Math.round((z - 0.1) * 100) / 100))
  }, [])

  const resetZoom = useCallback(() => {
    setZoom(1)
  }, [])

  const removeBackground = useCallback(async (itemId: string) => {
    const item = items.find((i) => i.id === itemId)
    if (!item || item.type !== 'image') return
    setIsRemovingBg(true)
    try {
      const { removeBackground: removeBg } = await import('@imgly/background-removal')
      const sourceContent = item.originalContent || item.content
      const blob = await removeBg(sourceContent, {
        output: { format: 'image/png' },
      })
      const reader = new FileReader()
      reader.onload = () => {
        updateItem(itemId, {
          content: reader.result as string,
          originalContent: sourceContent,
        })
        setIsRemovingBg(false)
      }
      reader.readAsDataURL(blob)
    } catch (err) {
      console.error('Background removal failed:', err)
      setIsRemovingBg(false)
    }
  }, [items, updateItem])

  const restoreBackground = useCallback((itemId: string) => {
    const item = items.find((i) => i.id === itemId)
    if (!item || !item.originalContent) return
    updateItem(itemId, { content: item.originalContent, originalContent: undefined })
  }, [items, updateItem])

  // Alignment functions
  const alignItems = useCallback((alignment: 'left' | 'right' | 'top' | 'bottom' | 'centerH' | 'centerV') => {
    if (selectedItems.length < 2) return
    setItems((prev) => {
      const selected = prev.filter((i) => selectedIds.has(i.id))
      const rest = prev.filter((i) => !selectedIds.has(i.id))

      let ref: number
      switch (alignment) {
        case 'left':
          ref = Math.min(...selected.map((i) => i.x))
          return [...rest, ...selected.map((i) => ({ ...i, x: ref }))]
        case 'right':
          ref = Math.max(...selected.map((i) => i.x + i.width))
          return [...rest, ...selected.map((i) => ({ ...i, x: ref - i.width }))]
        case 'top':
          ref = Math.min(...selected.map((i) => i.y))
          return [...rest, ...selected.map((i) => ({ ...i, y: ref }))]
        case 'bottom':
          ref = Math.max(...selected.map((i) => i.y + i.height))
          return [...rest, ...selected.map((i) => ({ ...i, y: ref - i.height }))]
        case 'centerH': {
          const minX = Math.min(...selected.map((i) => i.x))
          const maxX = Math.max(...selected.map((i) => i.x + i.width))
          const center = (minX + maxX) / 2
          return [...rest, ...selected.map((i) => ({ ...i, x: center - i.width / 2 }))]
        }
        case 'centerV': {
          const minY = Math.min(...selected.map((i) => i.y))
          const maxY = Math.max(...selected.map((i) => i.y + i.height))
          const center = (minY + maxY) / 2
          return [...rest, ...selected.map((i) => ({ ...i, y: center - i.height / 2 }))]
        }
      }
    })
  }, [selectedItems, selectedIds])

  const distributeItems = useCallback((direction: 'horizontal' | 'vertical') => {
    if (selectedItems.length < 3) return
    setItems((prev) => {
      const selected = prev.filter((i) => selectedIds.has(i.id))
      const rest = prev.filter((i) => !selectedIds.has(i.id))

      if (direction === 'horizontal') {
        const sorted = [...selected].sort((a, b) => a.x - b.x)
        const minX = sorted[0].x
        const maxX = sorted[sorted.length - 1].x + sorted[sorted.length - 1].width
        const totalItemWidth = sorted.reduce((sum, i) => sum + i.width, 0)
        const gap = (maxX - minX - totalItemWidth) / (sorted.length - 1)
        let currentX = minX
        const distributed = sorted.map((item) => {
          const newItem = { ...item, x: currentX }
          currentX += item.width + gap
          return newItem
        })
        return [...rest, ...distributed]
      } else {
        const sorted = [...selected].sort((a, b) => a.y - b.y)
        const minY = sorted[0].y
        const maxY = sorted[sorted.length - 1].y + sorted[sorted.length - 1].height
        const totalItemHeight = sorted.reduce((sum, i) => sum + i.height, 0)
        const gap = (maxY - minY - totalItemHeight) / (sorted.length - 1)
        let currentY = minY
        const distributed = sorted.map((item) => {
          const newItem = { ...item, y: currentY }
          currentY += item.height + gap
          return newItem
        })
        return [...rest, ...distributed]
      }
    })
  }, [selectedItems, selectedIds])

  const arrangeCollage = useCallback(() => {
    if (selectedItems.length < 2) return
    setItems((prev) => {
      const selected = prev.filter((i) => selectedIds.has(i.id))
      const rest = prev.filter((i) => !selectedIds.has(i.id))
      const startX = Math.min(...selected.map((i) => i.x))
      const startY = Math.min(...selected.map((i) => i.y))
      const n = selected.length

      let seed = n * 7 + 13
      const rand = () => { seed = (seed * 16807 + 0) % 2147483647; return (seed - 1) / 2147483646 }

      // Shuffle items deterministically
      const shuffled = [...selected]
      for (let i = shuffled.length - 1; i > 0; i--) {
        const j = Math.floor(rand() * (i + 1));
        [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]]
      }

      // Define a rectangular canvas area to fill densely
      // Scale area based on item count
      const areaW = Math.min(1400, 350 * Math.ceil(Math.sqrt(n)))
      const areaH = Math.min(1000, 300 * Math.ceil(n / Math.ceil(Math.sqrt(n))))

      // Assign each item a size class
      const placed: { id: string; x: number; y: number; w: number; h: number; rot: number; z: number }[] = []

      // Place items using a spiral/scatter approach that fills the area
      shuffled.forEach((item, idx) => {
        const aspect = Math.max(0.5, Math.min(2, item.width / item.height))

        // Size: first 2 are hero, then alternate between medium and small
        let targetW: number
        if (idx < 2) {
          targetW = 380 + rand() * 80 // hero: 380-460
        } else if (rand() < 0.35) {
          targetW = 300 + rand() * 60 // medium-large: 300-360
        } else if (rand() < 0.6) {
          targetW = 220 + rand() * 50 // medium: 220-270
        } else {
          targetW = 150 + rand() * 50 // small: 150-200
        }

        // Text items: keep reasonable width
        if (item.type === 'text') {
          targetW = Math.min(targetW, 240)
        }

        const w = Math.round(targetW)
        const h = Math.round(item.type === 'text' ? w / Math.max(aspect, 0.6) : w / aspect)

        // Position: scatter across the area with overlap
        // Use a grid-hint to spread items, then add jitter
        const cols = Math.ceil(Math.sqrt(n * 1.2))
        const cellW = areaW / cols
        const cellH = areaH / Math.ceil(n / cols)
        const gridCol = idx % cols
        const gridRow = Math.floor(idx / cols)

        // Base position from grid cell center, then heavy jitter
        const baseX = gridCol * cellW + cellW * 0.5 - w * 0.5
        const baseY = gridRow * cellH + cellH * 0.5 - h * 0.5
        const jitterX = (rand() - 0.5) * cellW * 0.7
        const jitterY = (rand() - 0.5) * cellH * 0.5

        const rotation = item.type === 'image'
          ? Math.round((rand() - 0.5) * 12 * 10) / 10 // -6 to +6 degrees
          : Math.round((rand() - 0.5) * 4 * 10) / 10  // -2 to +2 degrees

        // Text items get higher z so they sit on top of images
        const zBase = item.type === 'text' ? maxZIndex + n + idx : maxZIndex + idx

        placed.push({
          id: item.id,
          x: startX + Math.max(0, Math.round(baseX + jitterX)),
          y: startY + Math.max(0, Math.round(baseY + jitterY)),
          w, h,
          rot: rotation,
          z: zBase,
          isText: item.type === 'text',
        })
      })

      setMaxZIndex((prev) => prev + n * 2)

      // Auto bg colors for text items that don't have one
      const bgOptions = [
        'rgba(255,255,255,0.9)',
        'rgba(0,0,0,0.8)',
        'rgba(239,68,68,0.85)',
        'rgba(59,130,246,0.85)',
        'rgba(234,179,8,0.9)',
        'rgba(139,92,246,0.85)',
        'rgba(236,72,153,0.85)',
      ]
      let bgIdx = 0

      return [...rest, ...placed.map((p) => {
        const original = selected.find((i) => i.id === p.id)!
        const updates: Partial<BoardItem> = {
          x: p.x, y: p.y, width: p.w, height: p.h, rotation: p.rot, zIndex: p.z,
        }
        // Give text items a bg if they don't have one
        if (p.isText && (!original.bgColor || original.bgColor === 'transparent')) {
          updates.bgColor = bgOptions[bgIdx % bgOptions.length]
          // Set text color to white if bg is dark
          const bg = updates.bgColor
          if (bg.includes('0,0,0') || bg.includes('239,68,68') || bg.includes('59,130,246') || bg.includes('139,92,246') || bg.includes('236,72,153')) {
            updates.color = '#ffffff'
          }
          bgIdx++
        }
        return { ...original, ...updates }
      })]
    })
  }, [selectedItems, selectedIds, maxZIndex])

  const exportBoard = useCallback(() => {
    const data = JSON.stringify({ version: 1, items, maxZIndex }, null, 2)
    const blob = new Blob([data], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `vision-board-${new Date().toISOString().slice(0, 10)}.json`
    a.click()
    URL.revokeObjectURL(url)
    markBackedUp()
    setShowBackupReminder(false)
  }, [items, maxZIndex])

  // Board menu > Share as image: the clippings in view (or the whole board
  // when none are) as a 1080 x 1920 story with the VisionBoard mark
  const [sharingImage, setSharingImage] = useState(false)
  const shareAsImage = useCallback(async () => {
    const el = canvasRef.current
    if (!el || items.length === 0 || sharingImage) return
    setSharingImage(true)
    try {
      const left = el.scrollLeft / zoom
      const top = el.scrollTop / zoom
      const right = left + el.clientWidth / zoom
      const bottom = top + el.clientHeight / zoom
      const inView = items.filter(
        (i) => i.x < right && i.x + i.width > left && i.y < bottom && i.y + i.height > top,
      )
      const paper = canvasBgColors.find((c) => c.id === canvasBgColor)?.color ?? '#f5f0e8'
      const blob = await renderBoardStory(inView.length > 0 ? inView : items, paper, { mark: true, markLabel: t("share.mark") })
      if (!blob) return
      const method = await shareOrDownloadImage(blob, `visionboard-${new Date().toISOString().slice(0, 10)}.png`)
      if (method) {
        track("board_shared", { platform: "web", format: "story", method, has_mark: true, board_item_count: items.length })
      }
    } finally {
      setSharingImage(false)
    }
  }, [items, zoom, canvasBgColor, canvasBgColors, sharingImage, t])

  const importBoard = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => {
      try {
        const data = JSON.parse(reader.result as string)
        if (data.items && Array.isArray(data.items)) {
          setItems(data.items)
          setMaxZIndex(data.maxZIndex || data.items.length)
          setSelectedIds(new Set())
          // Auto fit after import
          requestAnimationFrame(() => fitAll())
        }
      } catch {
        console.error('Invalid board file')
      }
    }
    reader.readAsText(file)
    // Reset input so same file can be re-imported
    e.target.value = ''
  }, [fitAll])

  const cycleCanvasPattern = useCallback(() => {
    setCanvasPattern((prev) => {
      const idx = canvasPatternOptions.indexOf(prev)
      const next = canvasPatternOptions[(idx + 1) % canvasPatternOptions.length]
      localStorage.setItem('visionboard-canvas-pattern', next)
      return next
    })
  }, [])

  const updateSelectedItem = useCallback(
    (updates: Partial<BoardItem>) => {
      selectedIds.forEach((id) => updateItem(id, updates))
    },
    [selectedIds, updateItem]
  )

  // "I did it": marks a goal done (or back to a goal). The clipping stays on the board.
  const setAchieved = useCallback(
    (id: string, achieved: boolean) => {
      const item = items.find((i) => i.id === id)
      if (!item || !!item.achievedAt === achieved) return
      updateItem(id, { achievedAt: achieved ? new Date().toISOString() : undefined })
      const type = item.type === "image" ? "photo" : "text"
      if (achieved) {
        const days = daysSinceCreated(item)
        track("goal_achieved", days === null ? { type } : { type, days_since_created: days })
      } else {
        track("goal_unachieved", { type })
      }
    },
    [items, updateItem]
  )

  const toggleLock = useCallback(() => {
    const anyUnlocked = selectedItems.some((i) => !i.locked)
    selectedIds.forEach((id) => updateItem(id, { locked: anyUnlocked }))
  }, [selectedItems, selectedIds, updateItem])

  const getMultiDragStartPositions = useCallback(() => {
    const positions = new Map<string, { x: number; y: number }>()
    items.forEach((item) => {
      if (selectedIds.has(item.id)) {
        positions.set(item.id, { x: item.x, y: item.y })
      }
    })
    return positions
  }, [items, selectedIds])

  const handleMultiDragMove = useCallback((dx: number, dy: number, startPositions: Map<string, { x: number; y: number }>) => {
    setItems((prev) =>
      prev.map((item) => {
        const startPos = startPositions.get(item.id)
        if (!startPos || item.locked) return item
        return {
          ...item,
          x: Math.max(0, startPos.x + dx),
          y: Math.max(0, startPos.y + dy),
        }
      })
    )
  }, [])

  const cycleFontSize = useCallback(
    (direction: 1 | -1) => {
      if (!selectedItem || selectedItem.type !== "text") return
      const currentSize = selectedItem.fontSize || 18
      const idx = FONT_SIZES.indexOf(currentSize as (typeof FONT_SIZES)[number])
      if (idx === -1) {
        // Find closest
        const closest = FONT_SIZES.reduce((prev, curr) =>
          Math.abs(curr - currentSize) < Math.abs(prev - currentSize) ? curr : prev
        )
        updateSelectedItem({ fontSize: closest })
      } else {
        const nextIdx = Math.max(0, Math.min(FONT_SIZES.length - 1, idx + direction))
        updateSelectedItem({ fontSize: FONT_SIZES[nextIdx] })
      }
    },
    [selectedItem, updateSelectedItem]
  )

  return (
    <div className="flex h-screen flex-col bg-muted/30">
      {/* Toolbar */}
      <div className="flex items-center gap-1.5 sm:gap-2 border-b border-border bg-background/80 backdrop-blur-sm px-3 sm:px-4 py-2 sm:py-2.5 z-10">
        <h1 className="text-sm sm:text-base font-semibold tracking-tight text-foreground">
          vision board
        </h1>
        <div className="flex-1" />
        {/* Canvas pattern toggle */}
        <Button
          variant="ghost"
          size="sm"
          className="hidden sm:flex h-8 w-8 p-0 text-muted-foreground"
          title={canvasPattern === 'canvas-dots' ? t('toolbar.dots') : canvasPattern === 'canvas-grid' ? t('toolbar.grid') : t('toolbar.blank')}
          onClick={cycleCanvasPattern}
        >
          {canvasPattern === 'canvas-dots' && (
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
              <circle cx="3" cy="3" r="1.2" /><circle cx="8" cy="3" r="1.2" /><circle cx="13" cy="3" r="1.2" />
              <circle cx="3" cy="8" r="1.2" /><circle cx="8" cy="8" r="1.2" /><circle cx="13" cy="8" r="1.2" />
              <circle cx="3" cy="13" r="1.2" /><circle cx="8" cy="13" r="1.2" /><circle cx="13" cy="13" r="1.2" />
            </svg>
          )}
          {canvasPattern === 'canvas-grid' && (
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.2">
              <line x1="5.3" y1="0" x2="5.3" y2="16" /><line x1="10.7" y1="0" x2="10.7" y2="16" />
              <line x1="0" y1="5.3" x2="16" y2="5.3" /><line x1="0" y1="10.7" x2="16" y2="10.7" />
            </svg>
          )}
          {canvasPattern === 'canvas-blank' && (
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.2">
              <rect x="1" y="1" width="14" height="14" rx="2" />
            </svg>
          )}
        </Button>

        {/* Canvas bg color picker */}
        <Popover>
          <PopoverTrigger asChild>
            <Button variant="ghost" size="sm" className="hidden sm:flex h-8 w-8 p-0" title={t("toolbar.canvasColor")}>
              <div
                className="h-4 w-4 rounded-full border border-border"
                style={{ backgroundColor: canvasBgColors.find(c => c.id === canvasBgColor)?.color }}
              />
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-auto p-2" align="end" side="bottom">
            <div className="flex gap-1.5">
              {canvasBgColors.map((bg) => (
                <button
                  key={bg.id}
                  title={t(bg.label as MessageKey)}
                  className={`h-6 w-6 rounded-full border-2 transition-transform hover:scale-110 ${
                    canvasBgColor === bg.id
                      ? "border-blue-500 scale-110"
                      : "border-border"
                  }`}
                  style={{ backgroundColor: bg.color }}
                  onClick={() => {
                    setCanvasBgColor(bg.id as CanvasBgColor)
                    localStorage.setItem('visionboard-canvas-bg-color', bg.id)
                  }}
                />
              ))}
            </div>
          </PopoverContent>
        </Popover>

        {/* Zoom controls */}
        <div className="flex items-center gap-0.5 ml-1">
          <Button variant="ghost" size="sm" className="hidden sm:flex h-8 w-8 p-0 text-muted-foreground" title={t("toolbar.zoomOut")} onClick={zoomOut}>
            <ZoomOut className="h-4 w-4" />
          </Button>
          <button
            className="hidden sm:block text-xs text-muted-foreground w-10 text-center hover:text-foreground transition-colors"
            title={t("toolbar.resetZoom")}
            onClick={resetZoom}
          >
            {Math.round(zoom * 100)}%
          </button>
          <Button variant="ghost" size="sm" className="hidden sm:flex h-8 w-8 p-0 text-muted-foreground" title={t("toolbar.zoomIn")} onClick={zoomIn}>
            <ZoomIn className="h-4 w-4" />
          </Button>
          {items.length > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-8 gap-1.5 px-2 text-muted-foreground"
              title={t("toolbar.feed")}
              onClick={() => openFeed(true)}
            >
              <GalleryVerticalEnd className="h-4 w-4" />
              <span className="hidden sm:inline text-xs">{t("toolbar.feed")}</span>
            </Button>
          )}
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0 text-muted-foreground" title={t("toolbar.fitAll")} onClick={fitAll}>
            <Maximize className="h-4 w-4" />
          </Button>
        </div>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button size="sm" variant="outline" className="gap-2 text-sm">
              <Plus className="h-4 w-4" />
              {t("toolbar.add")}
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={addTextItem}>
              <Type className="mr-2 h-4 w-4" />
              {t("toolbar.text")}
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => fileInputRef.current?.click()}>
              <ImageIcon className="mr-2 h-4 w-4" />
              {t("toolbar.image")}
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => {
                setPhotoSearchOpen(true)
                track("photo_search_opened", { surface: "board" })
              }}
            >
              <Search className="mr-2 h-4 w-4" />
              {t("toolbar.searchPhotos")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
        <PhotoSearchDialog open={photoSearchOpen} onOpenChange={setPhotoSearchOpen} onAdd={addSearchPhotos} />
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          onChange={handleFileSelect}
          className="hidden"
        />

        {/* Board menu */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="sm" className="h-8 w-8 p-0" aria-label={t("toolbar.menu")}>
              <MoreVertical className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {sync.status !== "unavailable" && (
              <DropdownMenuItem onClick={() => setSyncOpen(true)}>
                <Cloud className="mr-2 h-4 w-4" />
                {t("menu.sync")}
              </DropdownMenuItem>
            )}
            {items.length > 0 && (
              <DropdownMenuItem onClick={shareAsImage} disabled={sharingImage}>
                <Share2 className="mr-2 h-4 w-4" />
                {t("menu.shareImage")}
              </DropdownMenuItem>
            )}
            <DropdownMenuItem onClick={exportBoard}>
              <Download className="mr-2 h-4 w-4" />
              {t("menu.export")}
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => importInputRef.current?.click()}>
              <Upload className="mr-2 h-4 w-4" />
              {t("menu.import")}
            </DropdownMenuItem>
            {items.length > 0 && (
              <DropdownMenuItem onClick={resetBoard} className="text-destructive focus:text-destructive">
                <RotateCw className="mr-2 h-4 w-4" />
                {t("menu.reset")}
              </DropdownMenuItem>
            )}
            {APP_STORE_URL && (
              <DropdownMenuItem asChild>
                <a
                  href={APP_STORE_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={() => track("app_store_clicked", { surface: "menu" })}
                >
                  <Smartphone className="mr-2 h-4 w-4" />
                  {t("menu.getApp")}
                </a>
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
            <div className="flex items-center justify-between gap-3 px-2 py-1.5 text-sm">
              <span className="text-muted-foreground">{t("menu.language")}</span>
              <div className="flex rounded-md border p-0.5 text-xs" role="group" aria-label={t("menu.language")}>
                {(["en", "es"] as const).map((l) => (
                  <button
                    key={l}
                    aria-pressed={lang === l}
                    className={cn(
                      "rounded px-2 py-0.5 font-medium transition-colors",
                      lang === l ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
                    )}
                    onClick={() => setLang(l)}
                  >
                    {l.toUpperCase()}
                  </button>
                ))}
              </div>
            </div>
            <div className="flex gap-3 px-2 pb-1.5 pt-1 text-xs text-muted-foreground">
              <a href={`/privacy?lang=${lang}`} className="hover:text-foreground">{t("legal.privacy")}</a>
              <a href={`/terms?lang=${lang}`} className="hover:text-foreground">{t("legal.terms")}</a>
              <a href={`/support?lang=${lang}`} className="hover:text-foreground">{t("legal.support")}</a>
            </div>
          </DropdownMenuContent>
        </DropdownMenu>
        <input
          ref={importInputRef}
          type="file"
          accept=".json"
          onChange={importBoard}
          className="hidden"
        />
      </div>

      {/* Welcome overlay, outside the transformed canvas so fixed positioning works */}
      {showWelcome && (
        <div className="absolute inset-0 top-[41px] sm:top-[49px] flex flex-col items-center z-20 pointer-events-none overflow-auto">
          <div className="my-auto flex flex-col items-center max-w-lg w-full px-4 sm:px-6 py-6 pointer-events-auto">
            {/* Hero */}
            <div className="text-center mb-5 sm:mb-6">
              <h2 className="text-xl sm:text-2xl font-bold tracking-tight text-foreground mb-2">
                {t("welcome.title")}
              </h2>
              <p className="text-xs sm:text-sm text-muted-foreground">
                {t("welcome.subtitle")}
              </p>
            </div>

            {/* Goals: three short fields that become the first board */}
            <form
              className="w-full rounded-xl border border-border/60 bg-background/80 backdrop-blur-sm p-3 sm:p-4 mb-6 sm:mb-8 shadow-sm"
              onSubmit={(e) => {
                e.preventDefault()
                makeGoalsBoard()
              }}
            >
              <p className="text-xs sm:text-sm font-medium text-foreground mb-2.5">{t("welcome.goalsLabel")}</p>
              <div className="flex flex-col gap-2">
                {goals.map((goal, i) => (
                  <Input
                    key={i}
                    ref={(el) => { goalRefs.current[i] = el }}
                    value={goal}
                    maxLength={80}
                    enterKeyHint={i < goals.length - 1 ? "next" : "done"}
                    aria-label={t("welcome.goalAria", { n: i + 1 })}
                    placeholder={t(`welcome.goal${i + 1}` as MessageKey)}
                    // 16px on phones so iOS doesn't zoom the page when focused
                    className="h-10 bg-background text-base sm:text-sm"
                    onChange={(e) => {
                      const value = e.target.value
                      setGoals((prev) => prev.map((g, j) => (j === i ? value : g)))
                    }}
                    onKeyDown={(e) => {
                      if (e.key !== "Enter" || e.nativeEvent.isComposing) return
                      if (i < goals.length - 1) {
                        e.preventDefault()
                        goalRefs.current[i + 1]?.focus()
                      }
                    }}
                  />
                ))}
              </div>
              <Button
                type="submit"
                className="mt-3 w-full gap-1.5"
                disabled={!goals.some((g) => g.trim())}
              >
                {t("welcome.make")}
                <ArrowRight className="h-4 w-4" />
              </Button>
            </form>

            {/* Templates */}
            <p className="self-start text-xs font-medium text-muted-foreground mb-2">{t("welcome.orExample")}</p>
            <div className="grid grid-cols-2 gap-2 sm:gap-3 w-full mb-6 sm:mb-8">
              {TEMPLATES.map((base) => {
                const tmpl = localizeTemplate(base, lang)
                return (
                  <button
                    key={tmpl.id}
                    onClick={() => loadTemplate(tmpl.id)}
                    className="group flex flex-col items-start gap-1 sm:gap-1.5 rounded-xl border border-border/60 bg-background/70 backdrop-blur-sm p-3 sm:p-4 text-left transition-all hover:border-border hover:bg-background hover:shadow-md active:scale-[0.98]"
                  >
                    <span className="text-lg sm:text-xl">{tmpl.emoji}</span>
                    <span className="text-xs sm:text-sm font-medium text-foreground">{tmpl.name}</span>
                    <span className="text-[11px] sm:text-xs text-muted-foreground leading-relaxed">{tmpl.description}</span>
                  </button>
                )
              })}
            </div>

            {/* Quick actions */}
            <div className="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
              <Button
                variant="outline"
                size="sm"
                className="gap-1.5 sm:gap-2 text-xs sm:text-sm"
                onClick={() => fileInputRef.current?.click()}
              >
                <ImageIcon className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
                {t("welcome.dropImage")}
              </Button>
              <Button
                variant="outline"
                size="sm"
                className="gap-1.5 sm:gap-2 text-xs sm:text-sm"
                onClick={addTextItem}
              >
                <Type className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
                {t("welcome.addWords")}
              </Button>
            </div>

            {sync.status !== "unavailable" && (
              <Button
                variant="ghost"
                size="sm"
                className="mt-3 gap-1.5 text-xs sm:text-sm text-muted-foreground"
                onClick={() => setSyncOpen(true)}
              >
                <Cloud className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
                {t("welcome.openOther")}
              </Button>
            )}

            {APP_STORE_URL && (
              <a
                href={APP_STORE_URL}
                target="_blank"
                rel="noopener noreferrer"
                onClick={() => track("app_store_clicked", { surface: "welcome" })}
                className="mt-4 inline-flex items-center gap-1.5 rounded-full bg-foreground px-4 py-2 text-xs sm:text-sm font-medium text-background shadow-sm transition-opacity hover:opacity-90"
              >
                <Smartphone className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
                {t("welcome.getApp")}
              </a>
            )}

            <p className="text-[10px] sm:text-xs text-muted-foreground/50 mt-4 sm:mt-6">
              {t("welcome.hint")}
            </p>

            <nav className="mt-3 flex gap-4 text-[10px] sm:text-xs text-muted-foreground/60">
              <a href={`/privacy?lang=${lang}`} className="hover:text-muted-foreground">{t("legal.privacy")}</a>
              <a href={`/terms?lang=${lang}`} className="hover:text-muted-foreground">{t("legal.terms")}</a>
              <a href={`/support?lang=${lang}`} className="hover:text-muted-foreground">{t("legal.support")}</a>
            </nav>
          </div>
        </div>
      )}

      {/* Canvas */}
      <div
        ref={canvasRef}
        onClick={handleCanvasClick}
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        className={`relative flex-1 overflow-auto ${canvasPattern} ${canvasBgColor}`}
        style={{ cursor: "default" }}
      >
        <div
          data-canvas="true"
          className="relative"
          style={{
            width: "3000px",
            height: "3000px",
            transform: `scale(${zoom})`,
            transformOrigin: "0 0",
            minWidth: zoom < 1 ? `${3000 * zoom}px` : '100%',
            minHeight: zoom < 1 ? `${3000 * zoom}px` : '100%',
          }}
        >
          {items.map((item) => (
            <BoardItemComponent
              key={item.id}
              item={item}
              isSelected={selectedIds.has(item.id)}
              isMultiSelected={selectedIds.size > 1 && selectedIds.has(item.id)}
              zoom={zoom}
              onSelect={(e?: React.MouseEvent) => {
                if (e && (e.shiftKey || e.metaKey)) {
                  setSelectedIds((prev) => {
                    const next = new Set(prev)
                    if (next.has(item.id)) {
                      next.delete(item.id)
                    } else {
                      next.add(item.id)
                    }
                    return next
                  })
                } else {
                  if (!selectedIds.has(item.id)) {
                    setSelectedIds(new Set([item.id]))
                  }
                }
                bringToFront(item.id)
              }}
              onUpdate={(updates) => updateItem(item.id, updates)}
              onDelete={() => deleteItem(item.id)}
              onMultiDragStart={getMultiDragStartPositions}
              onMultiDragMove={handleMultiDragMove}
            />
          ))}
        </div>
      </div>

      {/* Bottom toolbar - text formatting */}
      {selectedItem && selectedItem.type === "text" && (
        <div className="flex items-center gap-1.5 border-t border-border bg-background/80 backdrop-blur-sm px-3 sm:px-4 py-2 z-10 overflow-x-auto">
          {/* Text style picker */}
          <Popover>
            <PopoverTrigger asChild>
              <Button variant="ghost" size="sm" className="h-8 px-2.5 text-xs gap-1.5">
                <span className="font-medium">{TEXT_STYLES.find((st) => st.id === resolveStyle(selectedItem.fontStyle))?.label || 'Clean'}</span>
                <svg width="8" height="8" viewBox="0 0 8 8" fill="currentColor"><path d="M1 3l3 3 3-3" /></svg>
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-48 p-1.5" align="start" side="top">
              <div className="flex flex-col gap-0.5">
                {TEXT_STYLES.map((style) => (
                  <button
                    key={style.id}
                    className={cn(
                      "text-left px-2.5 py-1.5 rounded-md text-sm transition-colors hover:bg-accent",
                      resolveStyle(selectedItem.fontStyle) === style.id && "bg-accent"
                    )}
                    onClick={() => updateSelectedItem({ fontStyle: style.id })}
                  >
                    <span
                      style={{
                        fontFamily: style.fontFamily,
                        fontWeight: style.fontWeight,
                        fontStyle: style.fontStyle,
                        letterSpacing: style.letterSpacing,
                        textTransform: style.textTransform as React.CSSProperties['textTransform'],
                      }}
                    >
                      {style.label}
                    </span>
                  </button>
                ))}
              </div>
            </PopoverContent>
          </Popover>

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Font size */}
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            onClick={() => cycleFontSize(-1)}
          >
            <MinusIcon className="h-3 w-3" />
          </Button>
          <span className="text-xs font-mono w-8 text-center tabular-nums text-muted-foreground">
            {selectedItem.fontSize || 18}
          </span>
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            onClick={() => cycleFontSize(1)}
          >
            <PlusIcon className="h-3 w-3" />
          </Button>

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Color picker */}
          <Popover>
            <PopoverTrigger asChild>
              <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
                <div
                  className="h-4 w-4 rounded-full border border-border"
                  style={{ backgroundColor: selectedItem.color || "#1a1a1a" }}
                />
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-auto p-2" align="start" side="top">
              <div className="grid grid-cols-5 gap-1.5">
                {TEXT_COLORS.map((c) => (
                  <button
                    key={c}
                    className={`h-6 w-6 rounded-full border-2 transition-transform hover:scale-110 ${
                      (selectedItem.color || "#1a1a1a") === c
                        ? "border-blue-500 scale-110"
                        : "border-transparent"
                    }`}
                    style={{ backgroundColor: c }}
                    onClick={() => updateSelectedItem({ color: c })}
                  />
                ))}
              </div>
            </PopoverContent>
          </Popover>

          {/* Background color picker */}
          <Popover>
            <PopoverTrigger asChild>
              <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.bgColor")}>
                <PaintBucket className="h-4 w-4" style={{ color: selectedItem.bgColor && selectedItem.bgColor !== 'transparent' ? selectedItem.bgColor : undefined }} />
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-auto p-2" align="start" side="top">
              <div className="grid grid-cols-5 gap-1.5">
                <button
                  className={`h-6 w-6 rounded-full border-2 transition-transform hover:scale-110 relative ${
                    !selectedItem.bgColor || selectedItem.bgColor === 'transparent'
                      ? "border-blue-500 scale-110"
                      : "border-border"
                  }`}
                  style={{ backgroundColor: '#ffffff' }}
                  onClick={() => updateSelectedItem({ bgColor: 'transparent' })}
                >
                  <span className="absolute inset-0 flex items-center justify-center text-red-400 text-xs">/</span>
                </button>
                {['rgba(255,255,255,0.85)', 'rgba(0,0,0,0.75)', 'rgba(239,68,68,0.85)', 'rgba(59,130,246,0.85)', 'rgba(234,179,8,0.85)', 'rgba(34,197,94,0.85)', 'rgba(139,92,246,0.85)', 'rgba(236,72,153,0.85)', 'rgba(249,115,22,0.85)'].map((c) => (
                  <button
                    key={c}
                    className={`h-6 w-6 rounded-full border-2 transition-transform hover:scale-110 ${
                      selectedItem.bgColor === c
                        ? "border-blue-500 scale-110"
                        : "border-transparent"
                    }`}
                    style={{ backgroundColor: c }}
                    onClick={() => updateSelectedItem({ bgColor: c })}
                  />
                ))}
              </div>
            </PopoverContent>
          </Popover>

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Reset rotation */}
          {(selectedItem.rotation || 0) !== 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-8 gap-1.5 text-xs text-muted-foreground"
              onClick={() => updateSelectedItem({ rotation: 0 })}
            >
              <RotateCcw className="h-3 w-3" />
              {t("sel.reset")}
            </Button>
          )}

          <div className="mx-1 h-5 w-px bg-border" />

          {/* I did it */}
          <Button
            variant="ghost"
            size="sm"
            className={cn("h-8 gap-1.5 text-xs", selectedItem.achievedAt && "text-emerald-600")}
            title={selectedItem.achievedAt ? t("progress.notDone") : t("progress.markDone")}
            aria-pressed={!!selectedItem.achievedAt}
            onClick={() => setAchieved(selectedItem.id, !selectedItem.achievedAt)}
          >
            <BadgeCheck className="h-3.5 w-3.5" />
            {selectedItem.achievedAt ? t("progress.notDoneShort") : t("progress.didIt")}
          </Button>

          {/* Lock control */}
          <Button
            variant="ghost"
            size="sm"
            className={cn("h-8 w-8 p-0", selectedItem.locked && "text-amber-500")}
            title={selectedItem.locked ? t("sel.unlock") : t("sel.lock")}
            onClick={toggleLock}
          >
            {selectedItem.locked ? <Lock className="h-3.5 w-3.5" /> : <Unlock className="h-3.5 w-3.5" />}
          </Button>

          {/* Layer controls */}
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title={t("sel.front")}
            onClick={() => selectedIds.forEach((id) => bringToFront(id))}
          >
            <ArrowUpToLine className="h-3.5 w-3.5" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title={t("sel.back")}
            onClick={() => selectedIds.forEach((id) => sendToBack(id))}
          >
            <ArrowDownToLine className="h-3.5 w-3.5" />
          </Button>

          <div className="flex-1" />

          <Button
            variant="ghost"
            size="sm"
            onClick={() => { selectedIds.forEach((id) => deleteItem(id)); setSelectedIds(new Set()) }}
            className="h-8 gap-1.5 text-xs text-destructive hover:text-destructive"
          >
            <Trash2 className="h-3.5 w-3.5" />
            {t("sel.delete")}
          </Button>
        </div>
      )}

      {/* Bottom toolbar - multi-select alignment */}
      {selectedIds.size > 1 && (
        <div className="flex items-center gap-1.5 border-t border-border bg-background/80 backdrop-blur-sm px-3 sm:px-4 py-2 z-10 overflow-x-auto">
          <span className="text-xs text-muted-foreground mr-1">{t("sel.count", { n: selectedIds.size })}</span>

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Align */}
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.alignLeft")} onClick={() => alignItems('left')}>
            <AlignStartVertical className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.alignCenter")} onClick={() => alignItems('centerH')}>
            <AlignCenterVertical className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.alignRight")} onClick={() => alignItems('right')}>
            <AlignEndVertical className="h-3.5 w-3.5" />
          </Button>

          <div className="mx-0.5 h-5 w-px bg-border" />

          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.alignTop")} onClick={() => alignItems('top')}>
            <AlignStartHorizontal className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.alignMiddle")} onClick={() => alignItems('centerV')}>
            <AlignCenterHorizontal className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.alignBottom")} onClick={() => alignItems('bottom')}>
            <AlignEndHorizontal className="h-3.5 w-3.5" />
          </Button>

          {selectedIds.size >= 3 && (
            <>
              <div className="mx-0.5 h-5 w-px bg-border" />
              <Button variant="ghost" size="sm" className="h-8 gap-1 text-xs" title={t("sel.distH")} onClick={() => distributeItems('horizontal')}>
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <line x1="1" y1="1" x2="1" y2="13" /><line x1="13" y1="1" x2="13" y2="13" />
                  <rect x="5" y="3" width="4" height="8" rx="0.5" />
                </svg>
              </Button>
              <Button variant="ghost" size="sm" className="h-8 gap-1 text-xs" title={t("sel.distV")} onClick={() => distributeItems('vertical')}>
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <line x1="1" y1="1" x2="13" y2="1" /><line x1="1" y1="13" x2="13" y2="13" />
                  <rect x="3" y="5" width="8" height="4" rx="0.5" />
                </svg>
              </Button>
            </>
          )}

          <div className="mx-0.5 h-5 w-px bg-border" />

          {/* Grid arrange */}
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.collage")} onClick={arrangeCollage}>
            <LayoutGrid className="h-3.5 w-3.5" />
          </Button>

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Lock control */}
          <Button
            variant="ghost"
            size="sm"
            className={cn("h-8 w-8 p-0", selectedItems.every((i) => i.locked) && "text-amber-500")}
            title={selectedItems.some((i) => !i.locked) ? t("sel.lockAll") : t("sel.unlockAll")}
            onClick={toggleLock}
          >
            {selectedItems.every((i) => i.locked) ? <Lock className="h-3.5 w-3.5" /> : <Unlock className="h-3.5 w-3.5" />}
          </Button>

          {/* Layer controls */}
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.front")} onClick={() => selectedIds.forEach((id) => bringToFront(id))}>
            <ArrowUpToLine className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title={t("sel.back")} onClick={() => selectedIds.forEach((id) => sendToBack(id))}>
            <ArrowDownToLine className="h-3.5 w-3.5" />
          </Button>

          <div className="flex-1" />

          <Button
            variant="ghost"
            size="sm"
            onClick={() => { selectedIds.forEach((id) => deleteItem(id)); setSelectedIds(new Set()) }}
            className="h-8 gap-1.5 text-xs text-destructive hover:text-destructive"
          >
            <Trash2 className="h-3.5 w-3.5" />
            {t("sel.delete")}
          </Button>
        </div>
      )}

      {/* Bottom toolbar - image selected */}
      {selectedItem && selectedItem.type === "image" && (
        <div className="flex items-center gap-1.5 border-t border-border bg-background/80 backdrop-blur-sm px-3 sm:px-4 py-2 z-10 overflow-x-auto">
          {/* Remove / Restore background */}
          <Button
            variant="ghost"
            size="sm"
            className="h-8 gap-1.5 text-xs"
            disabled={isRemovingBg}
            onClick={() => removeBackground(selectedItem.id)}
          >
            {isRemovingBg ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              <Eraser className="h-3.5 w-3.5" />
            )}
            {isRemovingBg ? t("sel.removingBg") : t("sel.removeBg")}
          </Button>
          {selectedItem.originalContent && (
            <Button
              variant="ghost"
              size="sm"
              className="h-8 gap-1.5 text-xs text-muted-foreground"
              onClick={() => restoreBackground(selectedItem.id)}
            >
              <RotateCcw className="h-3 w-3" />
              {t("sel.restoreBg")}
            </Button>
          )}

          {selectedItem.credit && (
            <PhotoCredit credit={selectedItem.credit} className="px-2 text-xs text-muted-foreground" />
          )}

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Reset rotation */}
          {(selectedItem.rotation || 0) !== 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-8 gap-1.5 text-xs text-muted-foreground"
              onClick={() => updateSelectedItem({ rotation: 0 })}
            >
              <RotateCcw className="h-3 w-3" />
              {t("sel.resetRotation")}
            </Button>
          )}

          {/* I did it */}
          <Button
            variant="ghost"
            size="sm"
            className={cn("h-8 gap-1.5 text-xs", selectedItem.achievedAt && "text-emerald-600")}
            title={selectedItem.achievedAt ? t("progress.notDone") : t("progress.markDone")}
            aria-pressed={!!selectedItem.achievedAt}
            onClick={() => setAchieved(selectedItem.id, !selectedItem.achievedAt)}
          >
            <BadgeCheck className="h-3.5 w-3.5" />
            {selectedItem.achievedAt ? t("progress.notDoneShort") : t("progress.didIt")}
          </Button>

          {/* Lock control */}
          <Button
            variant="ghost"
            size="sm"
            className={cn("h-8 w-8 p-0", selectedItem.locked && "text-amber-500")}
            title={selectedItem.locked ? t("sel.unlock") : t("sel.lock")}
            onClick={toggleLock}
          >
            {selectedItem.locked ? <Lock className="h-3.5 w-3.5" /> : <Unlock className="h-3.5 w-3.5" />}
          </Button>

          {/* Layer controls */}
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title={t("sel.front")}
            onClick={() => selectedIds.forEach((id) => bringToFront(id))}
          >
            <ArrowUpToLine className="h-3.5 w-3.5" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title={t("sel.back")}
            onClick={() => selectedIds.forEach((id) => sendToBack(id))}
          >
            <ArrowDownToLine className="h-3.5 w-3.5" />
          </Button>

          <div className="flex-1" />

          <Button
            variant="ghost"
            size="sm"
            onClick={() => { selectedIds.forEach((id) => deleteItem(id)); setSelectedIds(new Set()) }}
            className="h-8 gap-1.5 text-xs text-destructive hover:text-destructive"
          >
            <Trash2 className="h-3.5 w-3.5" />
            {t("sel.delete")}
          </Button>
        </div>
      )}

      {feedOpen && (
        <FeedView
          items={items}
          onToggleLike={(id, liked) => {
            updateItem(id, { liked })
            if (liked) {
              const type = items.find((i) => i.id === id)?.type
              track("item_liked", { type: type === "image" ? "photo" : "text" })
            }
          }}
          onToggleAchieved={setAchieved}
          onClose={() => openFeed(false)}
        />
      )}

      {todayCard && <TodayCard card={todayCard} onClose={() => setTodayCard(null)} />}

      <SyncDialog
        open={syncOpen}
        onOpenChange={setSyncOpen}
        sync={sync}
        hasLocalItems={items.length > 0}
        linkKey={linkKey}
        onLinkHandled={() => setLinkKey(null)}
      />

      {showBackupReminder && (
        <div className="fixed top-[49px] sm:top-[57px] left-1/2 -translate-x-1/2 z-40 flex items-center gap-2 rounded-lg border bg-background/95 backdrop-blur px-3 py-2 shadow-sm text-xs max-w-[calc(100vw-32px)]">
          <span className="text-muted-foreground">
            {t("backup.text")}
          </span>
          {sync.status !== "unavailable" && (
            <Button variant="outline" size="sm" className="h-7 text-xs shrink-0" onClick={() => setSyncOpen(true)}>
              <Cloud className="mr-1.5 h-3.5 w-3.5" />
              {t("backup.sync")}
            </Button>
          )}
          <Button size="sm" className="h-7 text-xs shrink-0" onClick={exportBoard}>
            <Download className="mr-1.5 h-3.5 w-3.5" />
            {t("backup.backUp")}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 text-xs shrink-0"
            onClick={() => { snoozeBackupReminder(); setShowBackupReminder(false) }}
          >
            {t("backup.later")}
          </Button>
        </div>
      )}

      {/* Attribution */}
      <a
        href="https://kemenystudio.com"
        target="_blank"
        rel="noopener noreferrer"
        className="fixed bottom-1.5 right-2 sm:bottom-2 sm:right-3 text-[9px] sm:text-[10px] text-muted-foreground/40 hover:text-muted-foreground/70 transition-colors z-50"
      >
        kemenystudio.com
      </a>
    </div>
  )
}
