import { useEffect, useRef, useState } from 'react'
import { t } from '@/lib/i18n'

// Symbologies we read: QR (zones) plus the common 1D/2D barcodes on part labels.
const SCAN_FORMATS = [
  'qr_code', 'data_matrix', 'code_128', 'code_39',
  'ean_13', 'ean_8', 'upc_a', 'upc_e', 'itf', 'codabar',
] as const

// Ask for 720p: the default (often 640x480) leaves a small label's QR code
// too few pixels per module to read from a comfortable distance.
const VIDEO_CONSTRAINTS: MediaTrackConstraints = {
  facingMode: 'environment',
  width: { ideal: 1280 },
  height: { ideal: 720 },
}

// ZXing decodes in JavaScript, so it reads only the centered square the
// viewfinder shows, scaled down to at most this many pixels a side: a 720p
// frame read whole costs about twice as much and mostly holds background.
const ZXING_MAX_SIDE = 600
// Pause between two ZXing attempts, so the page stays responsive. (ZXing's
// own loop waits 500 ms, which is what made the fallback feel slow.)
const ZXING_PAUSE_MS = 40

// Minimal shape of the browser-native BarcodeDetector (not yet in TS DOM libs).
interface DetectedBarcode {
  rawValue: string
}
interface BarcodeDetectorInstance {
  detect(source: CanvasImageSource): Promise<DetectedBarcode[]>
}
interface BarcodeDetectorConstructor {
  new (options?: { formats?: string[] }): BarcodeDetectorInstance
  getSupportedFormats?(): Promise<string[]>
}

function describeCameraError(err: unknown): string {
  const e = err as { name?: string; message?: string }
  if (e?.name === 'NotAllowedError' || e?.name === 'SecurityError') {
    return t('Camera permission was denied. Allow camera access in your browser and try again.')
  }
  if (e?.name === 'NotFoundError' || e?.name === 'OverconstrainedError' || e?.name === 'DevicesNotFoundError') {
    return t('No camera was found on this device.')
  }
  if (e?.name === 'NotReadableError' || e?.name === 'TrackStartError') {
    return t('The camera is already in use by another application.')
  }
  return e?.message || t('Could not start the camera.')
}

// Continuous autofocus where the camera offers it (Android Chrome): a fixed
// focus leaves close-up labels blurred.
function keepFocusing(stream: MediaStream) {
  const track = stream.getVideoTracks()[0]
  const capabilities = (track?.getCapabilities?.() ?? {}) as { focusMode?: string[] }
  if (capabilities.focusMode?.includes('continuous')) {
    track.applyConstraints({ advanced: [ { focusMode: 'continuous' } as MediaTrackConstraintSet ] }).catch(() => undefined)
  }
}

// ZXing 0.23 logs a console warning (with a stack trace) for every symbology
// it fails to find, several times per frame: the browser keeps them all. This
// drops those while the camera runs and returns the function restoring warn.
function silenceZxingWarnings() {
  const warn = console.warn
  console.warn = (...args: unknown[]) => {
    if (typeof args[0] === 'string' && args[0].startsWith('MultiFormatReader:')) return
    warn.apply(console, args)
  }
  return () => {
    console.warn = warn
  }
}

interface BarcodeScannerOptions {
  // Keep the camera running after a read (counting several labels in a row).
  // The same code is then ignored for `repeatDelayMs`, so one label held in
  // front of the camera counts once. Otherwise the camera stops on the first read.
  continuous?: boolean
  repeatDelayMs?: number
}

/**
 * Camera barcode reading for a page: attach `videoRef` to an always-mounted
 * <video>, call `start()` from a click, and `onDecoded` receives each code.
 * Uses the browser's BarcodeDetector when there is one (Chrome, Android, Edge)
 * and falls back to ZXing (Safari, Firefox). The camera is released when the
 * page unmounts.
 */
export function useBarcodeScanner(onDecoded: (code: string) => void, { continuous = false, repeatDelayMs = 1500 }: BarcodeScannerOptions = {}) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const restoreWarnRef = useRef<(() => void) | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const rafRef = useRef<number | null>(null)
  const timerRef = useRef<number | null>(null)
  // Guards against firing multiple lookups from rapid consecutive detections.
  const scannedRef = useRef(false)
  const lastReadRef = useRef<{ code: string; at: number } | null>(null)
  const onDecodedRef = useRef(onDecoded)
  // Bumped by every stop(): a start() still awaiting the camera, play() or the
  // decoder checks it after each await and bails out (releasing a stream that
  // arrived late) instead of leaving the camera on after the page closed it.
  const sessionRef = useRef(0)
  const [active, setActive] = useState(false)
  const [starting, setStarting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    onDecodedRef.current = onDecoded
  }, [onDecoded])

  const stop = () => {
    sessionRef.current += 1
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
    if (timerRef.current != null) {
      window.clearTimeout(timerRef.current)
      timerRef.current = null
    }
    restoreWarnRef.current?.()
    restoreWarnRef.current = null
    streamRef.current?.getTracks().forEach((track) => track.stop())
    streamRef.current = null
    if (videoRef.current) videoRef.current.srcObject = null
    setActive(false)
    setStarting(false)
  }

  const handleDecoded = (text: string) => {
    const trimmed = text.trim()
    if (!trimmed || scannedRef.current) return

    if (continuous) {
      const now = Date.now()
      const last = lastReadRef.current
      if (last && last.code === trimmed && now - last.at < repeatDelayMs) return
      lastReadRef.current = { code: trimmed, at: now }
    } else {
      scannedRef.current = true
      stop()
    }
    navigator.vibrate?.(40)
    onDecodedRef.current(trimmed)
  }

  const start = async () => {
    setError(null)
    if (!navigator.mediaDevices?.getUserMedia) {
      setError(
        window.isSecureContext
          ? t('This browser does not support camera access.')
          : t('Camera access requires HTTPS. Open the app over https:// (or on localhost) to scan.'),
      )
      return
    }
    const session = ++sessionRef.current
    const cancelled = () => sessionRef.current !== session
    setStarting(true)
    setActive(true)
    scannedRef.current = false
    lastReadRef.current = null

    const BarcodeDetectorCtor = (window as unknown as { BarcodeDetector?: BarcodeDetectorConstructor }).BarcodeDetector

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: VIDEO_CONSTRAINTS })
      if (cancelled() || !videoRef.current) {
        // Stopped (or unmounted) while the permission prompt was open.
        stream.getTracks().forEach((track) => track.stop())
        return
      }
      streamRef.current = stream
      keepFocusing(stream)
      const video = videoRef.current
      video.srcObject = stream
      await video.play()
      if (cancelled()) return

      if (BarcodeDetectorCtor) {
        // Preferred path: the browser-native detector (Chrome/Android/Edge) is
        // far faster and more reliable than decoding every frame in JS.
        const supported = (await BarcodeDetectorCtor.getSupportedFormats?.()) ?? []
        if (cancelled()) return
        const formats = SCAN_FORMATS.filter((f) => supported.length === 0 || supported.includes(f))
        const detector = new BarcodeDetectorCtor(formats.length ? { formats: [ ...formats ] } : undefined)

        const scan = async () => {
          if (scannedRef.current || !streamRef.current || cancelled()) return
          try {
            const codes = await detector.detect(video)
            if (cancelled()) return
            if (codes.length > 0 && codes[0].rawValue) {
              handleDecoded(codes[0].rawValue)
              if (!continuous) return
            }
          } catch {
            // Transient decode errors (e.g. a not-yet-ready frame) — keep going.
          }
          rafRef.current = requestAnimationFrame(scan)
        }
        rafRef.current = requestAnimationFrame(scan)
      } else {
        // Fallback (Safari/Firefox): ZXing, restricted to the formats we use so
        // it locks on faster than scanning for every possible symbology, on
        // the visible square of each frame (see ZXING_MAX_SIDE).
        const [{ BrowserMultiFormatReader }, { DecodeHintType, BarcodeFormat }] = await Promise.all([
          import('@zxing/browser'),
          import('@zxing/library'),
        ])
        if (cancelled()) return
        const hints = new Map([
          [ DecodeHintType.POSSIBLE_FORMATS, [
            BarcodeFormat.QR_CODE, BarcodeFormat.DATA_MATRIX, BarcodeFormat.CODE_128,
            BarcodeFormat.CODE_39, BarcodeFormat.EAN_13, BarcodeFormat.EAN_8,
            BarcodeFormat.UPC_A, BarcodeFormat.UPC_E, BarcodeFormat.ITF, BarcodeFormat.CODABAR,
          ] ],
        ])
        const reader = new BrowserMultiFormatReader(hints)
        const canvas = document.createElement('canvas')
        const context = canvas.getContext('2d', { willReadFrequently: true })!
        restoreWarnRef.current = silenceZxingWarnings()

        const scan = () => {
          if (scannedRef.current || !streamRef.current || cancelled()) return
          const { videoWidth: width, videoHeight: height } = video
          if (width > 0 && height > 0) {
            const side = Math.min(width, height)
            const target = Math.min(side, ZXING_MAX_SIDE)
            if (canvas.width !== target) {
              canvas.width = target
              canvas.height = target
            }
            context.drawImage(video, (width - side) / 2, (height - side) / 2, side, side, 0, 0, target, target)
            try {
              handleDecoded(reader.decodeFromCanvas(canvas).getText())
              if (!continuous) return
            } catch {
              // Nothing readable in this frame — try the next one.
            }
          }
          timerRef.current = window.setTimeout(scan, ZXING_PAUSE_MS)
        }
        scan()
      }
    } catch (err) {
      if (cancelled()) return
      stop()
      setError(describeCameraError(err))
    } finally {
      if (!cancelled()) setStarting(false)
    }
  }

  // Always release the camera when leaving the page.
  useEffect(() => () => stop(), [])

  return { videoRef, active, starting, error, start, stop }
}
