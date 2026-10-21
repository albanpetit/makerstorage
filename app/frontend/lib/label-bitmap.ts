// Renders a QR label as a 1-bit bitmap at a label printer's exact resolution,
// for direct printing (LabelPrintersController#print). The layout follows the
// browser labels in labels.ts: the QR code on the left, title and lines on the
// right. Text is drawn by the browser, so the server never renders fonts.

import { type LabelItem, QR_QUIET_MODULES, type ZxingLibrary, qrMatrix, scanUrl } from '@/lib/labels'

export interface LabelGeometry {
  // Dots across the print head, and along the feed.
  width: number
  height: number
  dots_per_mm: number
}

const PT_TO_MM = 25.4 / 72
const SANS = 'Arial, Helvetica, sans-serif'
const MONO = 'ui-monospace, Menlo, Consolas, monospace'

interface TextLine {
  text: string
  font: string
  size: number
}

// Cuts +text+ to fit +width+, ending with an ellipsis when shortened.
function ellipsize(ctx: CanvasRenderingContext2D, text: string, width: number) {
  if (ctx.measureText(text).width <= width) return text
  let end = text.length
  while (end > 0 && ctx.measureText(`${text.slice(0, end)}…`).width > width) end--
  return `${text.slice(0, end)}…`
}

// Breaks +text+ anywhere (codes rarely have spaces) into at most +max+ lines.
function wrap(ctx: CanvasRenderingContext2D, text: string, width: number, max: number) {
  const lines: string[] = []
  let rest = text
  while (rest && lines.length < max - 1) {
    let end = rest.length
    while (end > 1 && ctx.measureText(rest.slice(0, end)).width > width) end--
    lines.push(rest.slice(0, end))
    rest = rest.slice(end)
  }
  if (rest) lines.push(ellipsize(ctx, rest, width))
  return lines
}

// Draws the label on a white canvas of +width+ × +height+ dots, as read.
function drawLabel(ctx: CanvasRenderingContext2D, zxing: ZxingLibrary, item: LabelItem, width: number, height: number, dotsPerMm: number) {
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, width, height)
  ctx.fillStyle = '#000'

  const padding = Math.round(1.5 * dotsPerMm)
  const matrix = qrMatrix(zxing, scanUrl(item.code))
  const modules = matrix.getWidth()
  const box = modules + QR_QUIET_MODULES * 2
  // Whole dots per module keep every module the same size on the printout.
  const scale = Math.max(1, Math.floor(Math.min(height - padding * 2, width * 0.5) / box))
  const qrSize = box * scale
  const qrTop = Math.round((height - qrSize) / 2)
  for (let y = 0; y < modules; y++) {
    for (let x = 0; x < modules; x++) {
      if (matrix.get(x, y) === 1) {
        ctx.fillRect(padding + (x + QR_QUIET_MODULES) * scale, qrTop + (y + QR_QUIET_MODULES) * scale, scale, scale)
      }
    }
  }

  const textLeft = padding + qrSize
  const textWidth = width - textLeft - padding
  if (textWidth < 5 * dotsPerMm) return

  const compact = height / dotsPerMm < 32
  const titleSize = (compact ? 8.5 : 10.5) * PT_TO_MM * dotsPerMm
  const lineSize = (compact ? 6.5 : 7.5) * PT_TO_MM * dotsPerMm

  const lines: TextLine[] = []
  ctx.font = `700 ${titleSize}px ${MONO}`
  for (const text of wrap(ctx, item.title, textWidth, 2)) lines.push({ text, font: ctx.font, size: titleSize })
  for (const text of item.lines.filter(Boolean)) {
    ctx.font = `${lineSize}px ${SANS}`
    lines.push({ text: ellipsize(ctx, text, textWidth), font: ctx.font, size: lineSize })
  }
  if (item.code !== item.title) {
    ctx.font = `${lineSize - 0.5 * PT_TO_MM * dotsPerMm}px ${MONO}`
    lines.push({ text: ellipsize(ctx, item.code, textWidth), font: ctx.font, size: lineSize })
  }

  // Keep what fits, centred vertically like the browser labels.
  const lineHeight = (line: TextLine) => line.size * 1.2
  while (lines.length > 1 && lines.reduce((sum, line) => sum + lineHeight(line), 0) > height - padding * 2) lines.pop()
  let y = (height - lines.reduce((sum, line) => sum + lineHeight(line), 0)) / 2
  ctx.textBaseline = 'middle'
  for (const line of lines) {
    ctx.font = line.font
    ctx.fillText(line.text, textLeft, y + lineHeight(line) / 2)
    y += lineHeight(line)
  }
}

// The label as a packed bitmap: rows of ceil(width / 8) bytes, most
// significant bit first, 1 = black. Labels longer than they are wide (along
// the feed) are drawn landscape and turned a quarter.
export function renderLabelBitmap(zxing: ZxingLibrary, item: LabelItem, geometry: LabelGeometry): Uint8Array {
  const { width, height, dots_per_mm: dotsPerMm } = geometry
  const rotate = height > width
  const canvas = document.createElement('canvas')
  canvas.width = rotate ? height : width
  canvas.height = rotate ? width : height
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) throw new Error('Canvas is not available.')

  drawLabel(ctx, zxing, item, canvas.width, canvas.height, dotsPerMm)
  const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data
  const dark = (x: number, y: number) => {
    const i = (y * canvas.width + x) * 4
    return pixels[i] * 0.299 + pixels[i + 1] * 0.587 + pixels[i + 2] * 0.114 < 128
  }

  const rowBytes = Math.ceil(width / 8)
  const bitmap = new Uint8Array(rowBytes * height)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      // Turned clockwise: the drawing's left edge runs along the feed.
      const black = rotate ? dark(y, canvas.height - 1 - x) : dark(x, y)
      if (black) bitmap[y * rowBytes + (x >> 3)] |= 0x80 >> (x & 7)
    }
  }
  return bitmap
}

export function bitmapToBase64(bitmap: Uint8Array) {
  let binary = ''
  for (let i = 0; i < bitmap.length; i += 0x8000) {
    binary += String.fromCharCode(...bitmap.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}
