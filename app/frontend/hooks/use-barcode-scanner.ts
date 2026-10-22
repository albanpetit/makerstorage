import { useEffect, useRef, useState } from 'react'
import type { IScannerControls } from '@zxing/browser'
import { t } from '@/lib/i18n'

// Symbologies we read: QR (zones) plus the common 1D/2D barcodes on part labels.
const SCAN_FORMATS = [
  'qr_code', 'data_matrix', 'code_128', 'code_39',
  'ean_13', 'ean_8', 'upc_a', 'upc_e', 'itf', 'codabar',
] as const

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
  const controlsRef = useRef<IScannerControls | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const rafRef = useRef<number | null>(null)
  // Guards against firing multiple lookups from rapid consecutive detections.
  const scannedRef = useRef(false)
  const lastReadRef = useRef<{ code: string; at: number } | null>(null)
  const onDecodedRef = useRef(onDecoded)
  onDecodedRef.current = onDecoded
  const [active, setActive] = useState(false)
  const [starting, setStarting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const stop = () => {
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
    controlsRef.current?.stop()
    controlsRef.current = null
    streamRef.current?.getTracks().forEach((track) => track.stop())
    streamRef.current = null
    if (videoRef.current) videoRef.current.srcObject = null
    setActive(false)
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
    setStarting(true)
    setActive(true)
    scannedRef.current = false
    lastReadRef.current = null

    const BarcodeDetectorCtor = (window as unknown as { BarcodeDetector?: BarcodeDetectorConstructor }).BarcodeDetector

    try {
      if (BarcodeDetectorCtor) {
        // Preferred path: the browser-native detector (Chrome/Android/Edge) is
        // far faster and more reliable than decoding every frame in JS.
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } })
        streamRef.current = stream
        const video = videoRef.current!
        video.srcObject = stream
        await video.play()

        const supported = (await BarcodeDetectorCtor.getSupportedFormats?.()) ?? []
        const formats = SCAN_FORMATS.filter((f) => supported.length === 0 || supported.includes(f))
        const detector = new BarcodeDetectorCtor(formats.length ? { formats: [ ...formats ] } : undefined)

        const scan = async () => {
          if (scannedRef.current || !streamRef.current) return
          try {
            const codes = await detector.detect(video)
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
        // it locks on faster than scanning for every possible symbology.
        const [{ BrowserMultiFormatReader }, { DecodeHintType, BarcodeFormat }] = await Promise.all([
          import('@zxing/browser'),
          import('@zxing/library'),
        ])
        const hints = new Map([
          [ DecodeHintType.POSSIBLE_FORMATS, [
            BarcodeFormat.QR_CODE, BarcodeFormat.DATA_MATRIX, BarcodeFormat.CODE_128,
            BarcodeFormat.CODE_39, BarcodeFormat.EAN_13, BarcodeFormat.EAN_8,
            BarcodeFormat.UPC_A, BarcodeFormat.UPC_E, BarcodeFormat.ITF, BarcodeFormat.CODABAR,
          ] ],
        ])
        const reader = new BrowserMultiFormatReader(hints)
        controlsRef.current = await reader.decodeFromConstraints(
          { video: { facingMode: 'environment' } },
          videoRef.current!,
          (decoded) => {
            if (decoded) handleDecoded(decoded.getText())
          },
        )
      }
    } catch (err) {
      stop()
      setError(describeCameraError(err))
    } finally {
      setStarting(false)
    }
  }

  // Always release the camera when leaving the page.
  useEffect(() => () => stop(), [])

  return { videoRef, active, starting, error, start, stop }
}
