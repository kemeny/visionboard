"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { BoardItem, FontStyle, TEXT_STYLES } from "@/lib/types"
import { cn } from "@/lib/utils"

interface BoardItemComponentProps {
  item: BoardItem
  isSelected: boolean
  isMultiSelected: boolean
  zoom: number
  onSelect: (e?: React.MouseEvent) => void
  onUpdate: (updates: Partial<BoardItem>) => void
  onDelete: () => void
  onMultiDragStart?: () => Map<string, { x: number; y: number }>
  onMultiDragMove?: (dx: number, dy: number, startPositions: Map<string, { x: number; y: number }>) => void
}

// Map old fontStyle values to new ones
const LEGACY_STYLE_MAP: Record<string, string> = {
  normal: 'clean',
  bold: 'loud',
  italic: 'editorial',
  serif: 'elegant',
}

function getTextStyle(fontStyle?: string) {
  const mapped = fontStyle && LEGACY_STYLE_MAP[fontStyle] ? LEGACY_STYLE_MAP[fontStyle] : fontStyle
  return TEXT_STYLES.find((s) => s.id === mapped) || TEXT_STYLES[0]
}

export function BoardItemComponent({
  item,
  isSelected,
  isMultiSelected,
  zoom,
  onSelect,
  onUpdate,
  onMultiDragStart,
  onMultiDragMove,
}: BoardItemComponentProps) {
  const [isDragging, setIsDragging] = useState(false)
  const [isResizing, setIsResizing] = useState(false)
  const [isEditing, setIsEditing] = useState(false)
  const [isRotating, setIsRotating] = useState(false)
  const [editContent, setEditContent] = useState(item.content)
  const elementRef = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const zoomRef = useRef(zoom)
  zoomRef.current = zoom
  const dragOffset = useRef({ x: 0, y: 0 })
  const dragStartMouse = useRef({ x: 0, y: 0 })
  const multiDragPositions = useRef<Map<string, { x: number; y: number }> | null>(null)
  const resizeStart = useRef({ x: 0, y: 0, width: 0, height: 0 })
  const rotateStart = useRef({ angle: 0, startAngle: 0 })

  useEffect(() => {
    if (isEditing && textareaRef.current) {
      textareaRef.current.focus()
      textareaRef.current.select()
    }
  }, [isEditing])

  // Shared start logic for mouse and touch
  const startDrag = useCallback(
    (clientX: number, clientY: number, e?: React.MouseEvent) => {
      if (isEditing || item.locked) return
      onSelect(e)

      const rect = elementRef.current?.getBoundingClientRect()
      if (rect) {
        dragOffset.current = {
          x: (clientX - rect.left) / zoomRef.current,
          y: (clientY - rect.top) / zoomRef.current,
        }
      }

      if (isMultiSelected && onMultiDragStart) {
        const z = zoomRef.current
        dragStartMouse.current = { x: clientX / z, y: clientY / z }
        multiDragPositions.current = onMultiDragStart()
      } else {
        multiDragPositions.current = null
      }

      setIsDragging(true)
    },
    [isEditing, item.locked, isMultiSelected, onSelect, onMultiDragStart]
  )

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation()
      startDrag(e.clientX, e.clientY, e)
    },
    [startDrag]
  )

  const handleTouchStart = useCallback(
    (e: React.TouchEvent) => {
      if (isEditing || item.locked) return
      const touch = e.touches[0]
      startDrag(touch.clientX, touch.clientY)
    },
    [isEditing, item.locked, startDrag]
  )

  const startResize = useCallback(
    (clientX: number, clientY: number) => {
      if (item.locked) return
      onSelect()
      resizeStart.current = {
        x: clientX,
        y: clientY,
        width: item.width,
        height: item.height,
      }
      setIsResizing(true)
    },
    [item.locked, onSelect, item.width, item.height]
  )

  const handleResizeMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation()
      startResize(e.clientX, e.clientY)
    },
    [startResize]
  )

  const handleResizeTouchStart = useCallback(
    (e: React.TouchEvent) => {
      e.stopPropagation()
      const touch = e.touches[0]
      startResize(touch.clientX, touch.clientY)
    },
    [startResize]
  )

  const startRotate = useCallback(
    (clientX: number, clientY: number) => {
      if (item.locked) return
      onSelect()
      const rect = elementRef.current?.getBoundingClientRect()
      if (rect) {
        const centerX = rect.left + rect.width / 2
        const centerY = rect.top + rect.height / 2
        const startAngle = Math.atan2(clientY - centerY, clientX - centerX) * (180 / Math.PI)
        rotateStart.current = {
          angle: item.rotation || 0,
          startAngle,
        }
      }
      setIsRotating(true)
    },
    [item.locked, onSelect, item.rotation]
  )

  const handleRotateMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation()
      startRotate(e.clientX, e.clientY)
    },
    [startRotate]
  )

  const handleRotateTouchStart = useCallback(
    (e: React.TouchEvent) => {
      e.stopPropagation()
      const touch = e.touches[0]
      startRotate(touch.clientX, touch.clientY)
    },
    [startRotate]
  )

  useEffect(() => {
    const handlePointerMove = (clientX: number, clientY: number) => {
      if (isDragging) {
        if (multiDragPositions.current && onMultiDragMove) {
          const z = zoomRef.current
          const dx = clientX / z - dragStartMouse.current.x
          const dy = clientY / z - dragStartMouse.current.y
          onMultiDragMove(dx, dy, multiDragPositions.current)
        } else {
          const parent = elementRef.current?.parentElement
          if (parent) {
            const parentRect = parent.getBoundingClientRect()
            const z = zoomRef.current
            const newX = (clientX - parentRect.left) / z - dragOffset.current.x
            const newY = (clientY - parentRect.top) / z - dragOffset.current.y
            onUpdate({
              x: Math.max(0, newX),
              y: Math.max(0, newY),
            })
          }
        }
      }
      if (isResizing) {
        const deltaX = (clientX - resizeStart.current.x) / zoomRef.current
        const deltaY = (clientY - resizeStart.current.y) / zoomRef.current
        onUpdate({
          width: Math.max(100, resizeStart.current.width + deltaX),
          height: Math.max(50, resizeStart.current.height + deltaY),
        })
      }
      if (isRotating) {
        const rect = elementRef.current?.getBoundingClientRect()
        if (rect) {
          const centerX = rect.left + rect.width / 2
          const centerY = rect.top + rect.height / 2
          const currentAngle = Math.atan2(clientY - centerY, clientX - centerX) * (180 / Math.PI)
          const delta = currentAngle - rotateStart.current.startAngle
          let newRotation = rotateStart.current.angle + delta
          if (Math.abs(newRotation % 360) < 5) newRotation = Math.round(newRotation / 360) * 360
          onUpdate({ rotation: newRotation })
        }
      }
    }

    const handleMouseMove = (e: MouseEvent) => handlePointerMove(e.clientX, e.clientY)
    const handleTouchMove = (e: TouchEvent) => {
      e.preventDefault()
      const touch = e.touches[0]
      handlePointerMove(touch.clientX, touch.clientY)
    }

    const handleEnd = () => {
      setIsDragging(false)
      setIsResizing(false)
      setIsRotating(false)
    }

    if (isDragging || isResizing || isRotating) {
      window.addEventListener("mousemove", handleMouseMove)
      window.addEventListener("mouseup", handleEnd)
      window.addEventListener("touchmove", handleTouchMove, { passive: false })
      window.addEventListener("touchend", handleEnd)
      window.addEventListener("touchcancel", handleEnd)
    }

    return () => {
      window.removeEventListener("mousemove", handleMouseMove)
      window.removeEventListener("mouseup", handleEnd)
      window.removeEventListener("touchmove", handleTouchMove)
      window.removeEventListener("touchend", handleEnd)
      window.removeEventListener("touchcancel", handleEnd)
    }
  }, [isDragging, isResizing, isRotating, onUpdate, onMultiDragMove])

  const clickCountRef = useRef(0)
  const clickTimeoutRef = useRef<NodeJS.Timeout | null>(null)

  const fontStyles: FontStyle[] = ['normal', 'bold', 'italic', 'serif']

  const cycleFontStyle = useCallback(() => {
    if (item.type !== 'text') return
    const currentIndex = fontStyles.indexOf(item.fontStyle || 'normal')
    const nextIndex = (currentIndex + 1) % fontStyles.length
    onUpdate({ fontStyle: fontStyles[nextIndex] })
  }, [item.type, item.fontStyle, onUpdate])

  const handleClick = useCallback(
    (e: React.MouseEvent) => {
      if (item.type !== 'text' || isEditing) return
      e.stopPropagation()

      clickCountRef.current += 1

      if (clickTimeoutRef.current) {
        clearTimeout(clickTimeoutRef.current)
      }

      clickTimeoutRef.current = setTimeout(() => {
        if (clickCountRef.current === 1) {
          cycleFontStyle()
        } else if (clickCountRef.current >= 3) {
          setIsEditing(true)
          setEditContent(item.content)
        }
        clickCountRef.current = 0
      }, 300)
    },
    [item.type, item.content, isEditing, cycleFontStyle]
  )

  const handleBlur = useCallback(() => {
    setIsEditing(false)
    if (editContent !== item.content) {
      onUpdate({ content: editContent })
    }
  }, [editContent, item.content, onUpdate])

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Escape") {
        setIsEditing(false)
        setEditContent(item.content)
      }
      if (e.key === "Enter" && e.metaKey) {
        handleBlur()
      }
    },
    [item.content, handleBlur]
  )

  const fontSize = item.fontSize || 18
  const color = item.color || '#1a1a1a'
  const bgColor = item.bgColor || 'transparent'
  const rotation = item.rotation || 0

  return (
    <div
      ref={elementRef}
      onMouseDown={handleMouseDown}
      onTouchStart={handleTouchStart}
      onClick={handleClick}
      className={cn(
        "absolute select-none transition-shadow duration-200",
        isSelected && "ring-2 ring-blue-500/80 ring-offset-2 ring-offset-transparent",
        item.locked && "cursor-default",
        !item.locked && isDragging && "cursor-grabbing",
        !item.locked && !isDragging && !isEditing && "cursor-grab"
      )}
      style={{
        left: item.x,
        top: item.y,
        width: item.width,
        height: item.height,
        zIndex: item.zIndex,
        transform: `rotate(${rotation}deg)`,
        transformOrigin: 'center center',
      }}
    >
      {item.type === "image" ? (
        <img
          src={item.content}
          alt="Vision board item"
          className="h-full w-full rounded-xl object-cover shadow-lg"
          draggable={false}
        />
      ) : (
        <div
          className={cn(
            "flex h-full w-full items-center justify-center p-4",
            bgColor !== 'transparent' && "rounded-xl"
          )}
          style={{ backgroundColor: bgColor }}
        >
          {(() => {
            const style = getTextStyle(item.fontStyle)
            const textStyle = {
              fontSize: `${fontSize}px`,
              lineHeight: style.lineHeight,
              color,
              fontFamily: style.fontFamily,
              fontWeight: style.fontWeight,
              fontStyle: style.fontStyle,
              letterSpacing: style.letterSpacing,
              textTransform: style.textTransform as React.CSSProperties['textTransform'],
            }
            return isEditing ? (
              <textarea
                ref={textareaRef}
                value={editContent}
                onChange={(e) => setEditContent(e.target.value)}
                onBlur={handleBlur}
                onKeyDown={handleKeyDown}
                className="h-full w-full resize-none bg-transparent text-center focus:outline-none"
                style={textStyle}
              />
            ) : (
              <p
                className="whitespace-pre-wrap text-center"
                style={textStyle}
              >
                {item.content}
              </p>
            )
          })()}
        </div>
      )}

      {/* Lock indicator */}
      {item.locked && isSelected && (
        <div className="absolute -top-3 -right-3 h-5 w-5 rounded-full bg-amber-500 flex items-center justify-center shadow-sm">
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
            <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        </div>
      )}

      {/* Resize handle */}
      {isSelected && !item.locked && (
        <>
          <div
            onMouseDown={handleResizeMouseDown}
            onTouchStart={handleResizeTouchStart}
            className="absolute -bottom-2 -right-2 h-5 w-5 cursor-se-resize rounded-full border-2 border-blue-500 bg-white shadow-sm sm:h-4 sm:w-4"
          />
          {/* Rotate handle */}
          <div
            onMouseDown={handleRotateMouseDown}
            onTouchStart={handleRotateTouchStart}
            className="absolute -top-10 left-1/2 -translate-x-1/2 flex flex-col items-center sm:-top-8"
          >
            <div className="h-5 w-px bg-blue-500/50 sm:h-4" />
            <div className="h-5 w-5 cursor-grab rounded-full border-2 border-blue-500 bg-white shadow-sm sm:h-3.5 sm:w-3.5" />
          </div>
        </>
      )}
    </div>
  )
}
