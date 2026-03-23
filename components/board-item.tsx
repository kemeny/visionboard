"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { BoardItem, FontStyle, TEXT_STYLES } from "@/lib/types"
import { cn } from "@/lib/utils"

interface BoardItemComponentProps {
  item: BoardItem
  isSelected: boolean
  zoom: number
  onSelect: (e?: React.MouseEvent) => void
  onUpdate: (updates: Partial<BoardItem>) => void
  onDelete: () => void
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
  zoom,
  onSelect,
  onUpdate,
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
  const resizeStart = useRef({ x: 0, y: 0, width: 0, height: 0 })
  const rotateStart = useRef({ angle: 0, startAngle: 0 })

  useEffect(() => {
    if (isEditing && textareaRef.current) {
      textareaRef.current.focus()
      textareaRef.current.select()
    }
  }, [isEditing])

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (isEditing) return
      e.stopPropagation()
      onSelect(e)

      const rect = elementRef.current?.getBoundingClientRect()
      if (rect) {
        dragOffset.current = {
          x: (e.clientX - rect.left) / zoomRef.current,
          y: (e.clientY - rect.top) / zoomRef.current,
        }
      }
      setIsDragging(true)
    },
    [isEditing, onSelect]
  )

  const handleResizeMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation()
      onSelect()
      resizeStart.current = {
        x: e.clientX,
        y: e.clientY,
        width: item.width,
        height: item.height,
      }
      setIsResizing(true)
    },
    [onSelect, item.width, item.height]
  )

  const handleRotateMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation()
      onSelect()
      const rect = elementRef.current?.getBoundingClientRect()
      if (rect) {
        const centerX = rect.left + rect.width / 2
        const centerY = rect.top + rect.height / 2
        const startAngle = Math.atan2(e.clientY - centerY, e.clientX - centerX) * (180 / Math.PI)
        rotateStart.current = {
          angle: item.rotation || 0,
          startAngle,
        }
      }
      setIsRotating(true)
    },
    [onSelect, item.rotation]
  )

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (isDragging) {
        const parent = elementRef.current?.parentElement
        if (parent) {
          const parentRect = parent.getBoundingClientRect()
          const z = zoomRef.current
          const newX = (e.clientX - parentRect.left) / z - dragOffset.current.x
          const newY = (e.clientY - parentRect.top) / z - dragOffset.current.y
          onUpdate({
            x: Math.max(0, newX),
            y: Math.max(0, newY),
          })
        }
      }
      if (isResizing) {
        const deltaX = (e.clientX - resizeStart.current.x) / zoomRef.current
        const deltaY = (e.clientY - resizeStart.current.y) / zoomRef.current
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
          const currentAngle = Math.atan2(e.clientY - centerY, e.clientX - centerX) * (180 / Math.PI)
          const delta = currentAngle - rotateStart.current.startAngle
          let newRotation = rotateStart.current.angle + delta
          // Snap to 0 when close
          if (Math.abs(newRotation % 360) < 5) newRotation = Math.round(newRotation / 360) * 360
          onUpdate({ rotation: newRotation })
        }
      }
    }

    const handleMouseUp = () => {
      setIsDragging(false)
      setIsResizing(false)
      setIsRotating(false)
    }

    if (isDragging || isResizing || isRotating) {
      window.addEventListener("mousemove", handleMouseMove)
      window.addEventListener("mouseup", handleMouseUp)
    }

    return () => {
      window.removeEventListener("mousemove", handleMouseMove)
      window.removeEventListener("mouseup", handleMouseUp)
    }
  }, [isDragging, isResizing, isRotating, onUpdate])

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
      onClick={handleClick}
      className={cn(
        "absolute select-none transition-shadow duration-200",
        isSelected && "ring-2 ring-blue-500/80 ring-offset-2 ring-offset-transparent",
        isDragging && "cursor-grabbing",
        !isDragging && !isEditing && "cursor-grab"
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

      {/* Resize handle */}
      {isSelected && (
        <>
          <div
            onMouseDown={handleResizeMouseDown}
            className="absolute -bottom-2 -right-2 h-4 w-4 cursor-se-resize rounded-full border-2 border-blue-500 bg-white shadow-sm"
          />
          {/* Rotate handle */}
          <div
            onMouseDown={handleRotateMouseDown}
            className="absolute -top-8 left-1/2 -translate-x-1/2 flex flex-col items-center"
          >
            <div className="h-4 w-px bg-blue-500/50" />
            <div className="h-3.5 w-3.5 cursor-grab rounded-full border-2 border-blue-500 bg-white shadow-sm" />
          </div>
        </>
      )}
    </div>
  )
}
