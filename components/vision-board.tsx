"use client"

import { useState, useRef, useCallback, useEffect } from "react"
import {
  Plus,
  Type,
  ImageIcon,
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
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { BoardItem, TEXT_COLORS, FONT_SIZES, TEXT_STYLES, FontStyle } from "@/lib/types"

const LEGACY_STYLE_MAP: Record<string, FontStyle> = {
  normal: 'clean', bold: 'loud', italic: 'editorial', serif: 'elegant',
}
function resolveStyle(fs?: string): FontStyle {
  if (!fs) return 'clean'
  if (LEGACY_STYLE_MAP[fs]) return LEGACY_STYLE_MAP[fs]
  return fs as FontStyle
}
import { saveItemsDB, loadItemsDB, saveMaxZDB, loadMaxZDB, migrateFromLocalStorage } from "@/lib/storage"
import { BoardItemComponent } from "./board-item"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"

export function VisionBoard() {
  const canvasPatternOptions = ['canvas-dots', 'canvas-grid', 'canvas-blank'] as const
  type CanvasPattern = typeof canvasPatternOptions[number]

  const canvasBgColors = [
    { id: 'canvas-bg-warm', label: 'Moleskine', color: '#f5f0e8' },
    { id: 'canvas-bg-cream', label: 'Cream', color: '#faf6ef' },
    { id: 'canvas-bg-gray', label: 'Gray', color: '#f0f0ee' },
    { id: 'canvas-bg-stone', label: 'Stone', color: '#eae6df' },
    { id: 'canvas-bg-white', label: 'White', color: '#ffffff' },
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
  }, [])

  // Save to IndexedDB on change
  useEffect(() => {
    if (!isLoaded) return
    saveItemsDB(items).catch(() => {})
  }, [items, isLoaded])

  useEffect(() => {
    if (!isLoaded) return
    saveMaxZDB(maxZIndex).catch(() => {})
  }, [maxZIndex, isLoaded])

  const generateId = () => Math.random().toString(36).substring(2, 9)

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
      content: "Click to style, triple-click to edit",
      zIndex: maxZIndex,
      fontStyle: "clean",
      fontSize: 18,
      color: "#1a1a1a",
      rotation: 0,
    }
    setItems((prev) => [...prev, newItem])
    setMaxZIndex((prev) => prev + 1)
    setSelectedIds(new Set([newItem.id]))
  }, [maxZIndex])

  const handleImageUpload = useCallback(
    (file: File) => {
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
      }
      reader.readAsDataURL(file)
    },
    [maxZIndex]
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
            handleImageUpload(file)
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
        handleImageUpload(imageFile)
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
  }, [items, maxZIndex])

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
      <div className="flex items-center gap-2 border-b border-border bg-background/80 backdrop-blur-sm px-4 py-2.5 z-10">
        <h1 className="text-base font-semibold tracking-tight text-foreground">
          Vision Board
        </h1>
        <div className="flex-1" />
        {/* Canvas pattern toggle */}
        <Button
          variant="ghost"
          size="sm"
          className="h-8 w-8 p-0 text-muted-foreground"
          title={canvasPattern === 'canvas-dots' ? 'Dots' : canvasPattern === 'canvas-grid' ? 'Grid' : 'Blank'}
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
            <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Canvas color">
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
                  title={bg.label}
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
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0 text-muted-foreground" title="Zoom out" onClick={zoomOut}>
            <ZoomOut className="h-4 w-4" />
          </Button>
          <button
            className="text-xs text-muted-foreground w-10 text-center hover:text-foreground transition-colors"
            title="Reset zoom"
            onClick={resetZoom}
          >
            {Math.round(zoom * 100)}%
          </button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0 text-muted-foreground" title="Zoom in" onClick={zoomIn}>
            <ZoomIn className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0 text-muted-foreground" title="Fit all" onClick={fitAll}>
            <Maximize className="h-4 w-4" />
          </Button>
        </div>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button size="sm" variant="outline" className="gap-2 text-sm">
              <Plus className="h-4 w-4" />
              Add
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={addTextItem}>
              <Type className="mr-2 h-4 w-4" />
              Text
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => fileInputRef.current?.click()}>
              <ImageIcon className="mr-2 h-4 w-4" />
              Image
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
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
            <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
              <MoreVertical className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={exportBoard}>
              <Download className="mr-2 h-4 w-4" />
              Export board
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => importInputRef.current?.click()}>
              <Upload className="mr-2 h-4 w-4" />
              Import board
            </DropdownMenuItem>
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
          {isLoaded && items.length === 0 && (
            <div className="fixed inset-0 flex flex-col items-center justify-center text-muted-foreground pointer-events-none z-0">
              <div className="flex flex-col items-center gap-5 rounded-2xl border border-dashed border-border/60 p-10 bg-background/50 backdrop-blur-sm">
                <div className="flex gap-3 text-muted-foreground/60">
                  <Type className="h-10 w-10" strokeWidth={1.5} />
                  <ImageIcon className="h-10 w-10" strokeWidth={1.5} />
                </div>
                <div className="text-center space-y-1">
                  <p className="text-sm font-medium text-muted-foreground">
                    Your board is empty
                  </p>
                  <p className="text-xs text-muted-foreground/70">
                    Add text or images &middot; Drag & drop &middot; Paste from clipboard
                  </p>
                </div>
              </div>
            </div>
          )}
          {items.map((item) => (
            <BoardItemComponent
              key={item.id}
              item={item}
              isSelected={selectedIds.has(item.id)}
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
                  setSelectedIds(new Set([item.id]))
                }
                bringToFront(item.id)
              }}
              onUpdate={(updates) => updateItem(item.id, updates)}
              onDelete={() => deleteItem(item.id)}
            />
          ))}
        </div>
      </div>

      {/* Bottom toolbar - text formatting */}
      {selectedItem && selectedItem.type === "text" && (
        <div className="flex items-center gap-1.5 border-t border-border bg-background/80 backdrop-blur-sm px-4 py-2 z-10">
          {/* Text style picker */}
          <Popover>
            <PopoverTrigger asChild>
              <Button variant="ghost" size="sm" className="h-8 px-2.5 text-xs gap-1.5">
                <span className="font-medium">{TEXT_STYLES.find((s) => s.id === resolveStyle(selectedItem.fontStyle))?.label || 'Clean'}</span>
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
              <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Background color">
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
              Reset
            </Button>
          )}

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Layer controls */}
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title="Bring to front"
            onClick={() => selectedIds.forEach((id) => bringToFront(id))}
          >
            <ArrowUpToLine className="h-3.5 w-3.5" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title="Send to back"
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
            Delete
          </Button>
        </div>
      )}

      {/* Bottom toolbar - multi-select alignment */}
      {selectedIds.size > 1 && (
        <div className="flex items-center gap-1.5 border-t border-border bg-background/80 backdrop-blur-sm px-4 py-2 z-10">
          <span className="text-xs text-muted-foreground mr-1">{selectedIds.size} selected</span>

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Align */}
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Align left" onClick={() => alignItems('left')}>
            <AlignStartVertical className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Align center" onClick={() => alignItems('centerH')}>
            <AlignCenterVertical className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Align right" onClick={() => alignItems('right')}>
            <AlignEndVertical className="h-3.5 w-3.5" />
          </Button>

          <div className="mx-0.5 h-5 w-px bg-border" />

          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Align top" onClick={() => alignItems('top')}>
            <AlignStartHorizontal className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Align middle" onClick={() => alignItems('centerV')}>
            <AlignCenterHorizontal className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Align bottom" onClick={() => alignItems('bottom')}>
            <AlignEndHorizontal className="h-3.5 w-3.5" />
          </Button>

          {selectedIds.size >= 3 && (
            <>
              <div className="mx-0.5 h-5 w-px bg-border" />
              <Button variant="ghost" size="sm" className="h-8 gap-1 text-xs" title="Distribute horizontally" onClick={() => distributeItems('horizontal')}>
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <line x1="1" y1="1" x2="1" y2="13" /><line x1="13" y1="1" x2="13" y2="13" />
                  <rect x="5" y="3" width="4" height="8" rx="0.5" />
                </svg>
              </Button>
              <Button variant="ghost" size="sm" className="h-8 gap-1 text-xs" title="Distribute vertically" onClick={() => distributeItems('vertical')}>
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <line x1="1" y1="1" x2="13" y2="1" /><line x1="1" y1="13" x2="13" y2="13" />
                  <rect x="3" y="5" width="8" height="4" rx="0.5" />
                </svg>
              </Button>
            </>
          )}

          <div className="mx-0.5 h-5 w-px bg-border" />

          {/* Grid arrange */}
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Arrange as collage" onClick={arrangeCollage}>
            <LayoutGrid className="h-3.5 w-3.5" />
          </Button>

          <div className="mx-1 h-5 w-px bg-border" />

          {/* Layer controls */}
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Bring to front" onClick={() => selectedIds.forEach((id) => bringToFront(id))}>
            <ArrowUpToLine className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" className="h-8 w-8 p-0" title="Send to back" onClick={() => selectedIds.forEach((id) => sendToBack(id))}>
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
            Delete
          </Button>
        </div>
      )}

      {/* Bottom toolbar - image selected */}
      {selectedItem && selectedItem.type === "image" && (
        <div className="flex items-center gap-1.5 border-t border-border bg-background/80 backdrop-blur-sm px-4 py-2 z-10">
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
            {isRemovingBg ? 'Removing…' : 'Remove BG'}
          </Button>
          {selectedItem.originalContent && (
            <Button
              variant="ghost"
              size="sm"
              className="h-8 gap-1.5 text-xs text-muted-foreground"
              onClick={() => restoreBackground(selectedItem.id)}
            >
              <RotateCcw className="h-3 w-3" />
              Restore BG
            </Button>
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
              Reset rotation
            </Button>
          )}

          {/* Layer controls */}
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title="Bring to front"
            onClick={() => selectedIds.forEach((id) => bringToFront(id))}
          >
            <ArrowUpToLine className="h-3.5 w-3.5" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-8 w-8 p-0"
            title="Send to back"
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
            Delete
          </Button>
        </div>
      )}
    </div>
  )
}
