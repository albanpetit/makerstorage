import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { router } from '@inertiajs/react'

import {
  OfflineLookup,
  ServerUnreachable,
  downloadSnapshot,
  keepScannerPageOffline,
  loadQueue,
  loadSnapshot,
  pendingScan,
  sendQueue,
  serverReachable,
  updateQueue,
  type OfflineSnapshot,
  type PendingScan,
} from '@/lib/offline-scanner'

// A snapshot older than this is refreshed when the page opens online.
const SNAPSHOT_MAX_AGE_MS = 5 * 60 * 1000
// How often an offline page checks whether the server answers again.
const PROBE_INTERVAL_MS = 15 * 1000

interface Options {
  organizationId: number | null
  // Whose device data this is (scans queued by one user are never sent as another).
  userKey: string | null
  canWrite: boolean
}

/**
 * Offline mode of the Scanner page (see lib/offline-scanner): whether the
 * server answers, the snapshot to answer scans from when it doesn't, and the
 * scans waiting to be sent, which go out as soon as it answers again.
 */
export function useOfflineScanner({ organizationId, userKey, canWrite }: Options) {
  const [online, setOnline] = useState(() => navigator.onLine)
  const [snapshot, setSnapshot] = useState<OfflineSnapshot | null>(null)
  const [queue, setQueue] = useState<PendingScan[]>([])
  const [syncing, setSyncing] = useState(false)
  const [storageError, setStorageError] = useState(false)
  const [pageKept, setPageKept] = useState(false)
  const syncingRef = useRef(false)

  const pending = useMemo(
    () => queue.filter((scan) => scan.organization_id === organizationId),
    [queue, organizationId],
  )

  const refreshSnapshot = useCallback(async () => {
    if (!userKey) return null
    try {
      const fresh = await downloadSnapshot(userKey)
      setSnapshot(fresh.snapshot)
      setOnline(true)
      return fresh
    } catch (error) {
      if (error instanceof ServerUnreachable) setOnline(false)
      return null
    }
  }, [userKey])

  const sync = useCallback(async () => {
    if (!userKey || !organizationId || !canWrite || syncingRef.current) return
    const toSend = (await loadQueue(userKey)).filter((scan) => scan.organization_id === organizationId && !scan.error)
    if (toSend.length === 0) return

    syncingRef.current = true
    setSyncing(true)
    try {
      const fresh = await refreshSnapshot()
      if (!fresh) return
      const results = await sendQueue(organizationId, toSend, fresh.csrfToken)
      const byId = new Map(results.map((result) => [result.id, result]))
      setQueue(await updateQueue(userKey, (current) => current.flatMap((scan) => {
        const result = byId.get(scan.id)
        if (!result) return [scan]
        if (result.status === 'rejected') return [{ ...scan, error: result.error ?? '' }]
        return []
      })))
      await refreshSnapshot()
      // The written movements show in "Recent scans" and the counts of the day.
      router.reload({ only: ['recent_scans', 'today_count'] })
    } catch (error) {
      if (error instanceof ServerUnreachable) setOnline(false)
    } finally {
      syncingRef.current = false
      setSyncing(false)
    }
  }, [userKey, organizationId, canWrite, refreshSnapshot])

  // What's on the device for this user and organization.
  useEffect(() => {
    if (!userKey || !organizationId) return
    let cancelled = false
    Promise.all([loadSnapshot(userKey, organizationId), loadQueue(userKey)])
      .then(([stored, storedQueue]) => {
        if (cancelled) return
        setSnapshot(stored ?? null)
        setQueue(storedQueue)
        const stale = !stored || Date.now() - new Date(stored.generated_at).getTime() > SNAPSHOT_MAX_AGE_MS
        if (navigator.onLine) {
          if (storedQueue.some((scan) => scan.organization_id === organizationId && !scan.error)) void sync()
          else if (stale) void refreshSnapshot()
        }
      })
      .catch(() => !cancelled && setStorageError(true))
    return () => {
      cancelled = true
    }
  }, [userKey, organizationId, refreshSnapshot, sync])

  // Keep the page itself for reopening offline. Browsers without a native
  // barcode reader load ZXing on demand: fetch it now so it's kept too.
  useEffect(() => {
    const warm = 'BarcodeDetector' in window ? Promise.resolve() : Promise.all([import('@zxing/browser'), import('@zxing/library')])
    warm.catch(() => undefined).then(() => keepScannerPageOffline()).then(setPageKept)
  }, [])

  useEffect(() => {
    const goOnline = () => {
      setOnline(true)
      void sync()
    }
    const goOffline = () => setOnline(false)
    window.addEventListener('online', goOnline)
    window.addEventListener('offline', goOffline)
    return () => {
      window.removeEventListener('online', goOnline)
      window.removeEventListener('offline', goOffline)
    }
  }, [sync])

  // The network link can be up while the server isn't reachable (out of
  // Wi-Fi range of a LAN install…): check now and then until it answers.
  useEffect(() => {
    if (online) return
    const timer = window.setInterval(async () => {
      if (navigator.onLine && await serverReachable()) {
        setOnline(true)
        void sync()
      }
    }, PROBE_INTERVAL_MS)
    return () => window.clearInterval(timer)
  }, [online, sync])

  const lookup = useMemo(() => (snapshot ? new OfflineLookup(snapshot, pending) : null), [snapshot, pending])

  const enqueue = useCallback(async (scan: Omit<PendingScan, 'id' | 'scanned_at' | 'organization_id'>) => {
    if (!userKey || !organizationId) return
    const entry = pendingScan({ ...scan, organization_id: organizationId })
    setQueue(await updateQueue(userKey, (current) => [...current, entry]))
  }, [userKey, organizationId])

  const discard = useCallback(async (id: string) => {
    if (!userKey) return
    setQueue(await updateQueue(userKey, (current) => current.filter((scan) => scan.id !== id)))
  }, [userKey])

  return {
    online,
    // Scans are answered on the device: the server doesn't answer and there is a snapshot.
    active: !online && !!lookup,
    lookup,
    snapshot,
    pending,
    syncing,
    storageError,
    pageKept,
    markUnreachable: useCallback(() => setOnline(false), []),
    refreshSnapshot,
    sync,
    enqueue,
    discard,
  }
}
