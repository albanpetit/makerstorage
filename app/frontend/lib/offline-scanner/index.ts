// The Scanner page without a network: a snapshot of the organization's parts
// and zones kept on the device (GET /scan/offline), a queue of the counts and
// bag receipts recorded meanwhile (sent with POST /scan/sync once the server
// answers again), and a service worker that keeps the page itself so it can be
// reopened offline (app/views/pwa/service-worker.js; HTTPS or localhost only).
import { deletePrefix, getItem, setItem, updateItem } from './store'
import type { OfflineSnapshot, PendingScan } from './lookup'

export * from './lookup'

export interface SyncResult {
  id: string
  status: 'saved' | 'duplicate' | 'rejected'
  error?: string
}

export class ServerUnreachable extends Error {}

const snapshotKey = (userKey: string, organizationId: number) => `snapshot:${userKey}:${organizationId}`
const queueKey = (userKey: string) => `queue:${userKey}`

export function loadSnapshot(userKey: string, organizationId: number) {
  return getItem<OfflineSnapshot>(snapshotKey(userKey, organizationId))
}

export async function loadQueue(userKey: string): Promise<PendingScan[]> {
  return (await getItem<PendingScan[]>(queueKey(userKey))) ?? []
}

export function updateQueue(userKey: string, change: (queue: PendingScan[]) => PendingScan[]) {
  return updateItem<PendingScan[]>(queueKey(userKey), (queue) => change(queue ?? []))
}

async function request(input: string, init: RequestInit = {}): Promise<Response> {
  try {
    return await fetch(input, {
      credentials: 'same-origin',
      cache: 'no-store',
      ...init,
      headers: { Accept: 'application/json', ...init.headers },
    })
  } catch {
    throw new ServerUnreachable()
  }
}

/** Downloads a fresh snapshot and keeps it. Returns it with a CSRF token for /scan/sync. */
export async function downloadSnapshot(userKey: string): Promise<{ snapshot: OfflineSnapshot; csrfToken: string }> {
  const response = await request('/scan/offline')
  // A signed-out session is redirected to the sign-in page (HTML).
  if (!response.ok || !response.headers.get('content-type')?.includes('json')) {
    throw new Error(`snapshot ${response.status}`)
  }
  const { csrf_token: csrfToken, ...snapshot } = await response.json() as OfflineSnapshot & { csrf_token: string }
  await setItem(snapshotKey(userKey, snapshot.organization_id), snapshot)
  return { snapshot, csrfToken }
}

/** Sends this organization's queued scans; returns the server's answer for each. */
export async function sendQueue(organizationId: number, scans: PendingScan[], csrfToken: string): Promise<SyncResult[]> {
  const response = await request('/scan/sync', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
    body: JSON.stringify({
      organization_id: organizationId,
      operations: scans.map(({ id, kind, part_id, storage_location_id, quantity, reference, scanned_at }) => (
        { id, kind, part_id, storage_location_id, quantity, reference, scanned_at }
      )),
    }),
  })
  if (!response.ok) throw new Error(`sync ${response.status}`)
  return ((await response.json()) as { results: SyncResult[] }).results
}

/** Is the server answering? (navigator.onLine only knows about the network link.) */
export async function serverReachable(): Promise<boolean> {
  try {
    const response = await fetch('/up', { method: 'HEAD', cache: 'no-store' })
    return response.ok
  } catch {
    return false
  }
}

function newId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`
}

export function pendingScan(fields: Omit<PendingScan, 'id' | 'scanned_at'>): PendingScan {
  return { ...fields, id: newId(), scanned_at: new Date().toISOString() }
}

const SERVICE_WORKER_URL = '/service-worker.js'
// Named in app/views/pwa/service-worker.js too.
const SCANNER_CACHE = 'makerstorage-scanner'

/**
 * Registers the service worker (secure contexts only) and asks it to keep the
 * Scanner page and the files this page loaded, so the page opens offline.
 */
export async function keepScannerPageOffline(): Promise<boolean> {
  if (!('serviceWorker' in navigator) || !window.isSecureContext) return false
  try {
    await navigator.serviceWorker.register(SERVICE_WORKER_URL, { scope: '/' })
    const registration = await navigator.serviceWorker.ready
    const urls = new Set<string>()
    document.querySelectorAll<HTMLScriptElement>('script[src]').forEach((script) => urls.add(script.src))
    document.querySelectorAll<HTMLLinkElement>('link[rel="stylesheet"], link[rel="modulepreload"], link[rel="icon"], link[rel="manifest"]').forEach((link) => urls.add(link.href))
    performance.getEntriesByType('resource').forEach((entry) => urls.add(entry.name))
    const sameOrigin = [...urls].filter((url) => {
      try {
        return new URL(url).origin === location.origin
      } catch {
        return false
      }
    })
    registration.active?.postMessage({ type: 'keep-scanner', urls: sameOrigin })
    return true
  } catch {
    return false
  }
}

/**
 * Forgets what the scanner kept on this device when signing out: the
 * snapshots and the cached page. Scans still waiting to be sent are kept (per
 * user) and go out at the next sign-in.
 */
export async function clearOfflineData(): Promise<void> {
  await Promise.allSettled([
    deletePrefix('snapshot:'),
    // Cache Storage only exists in secure contexts (see service-worker.js).
    typeof caches !== 'undefined' ? caches.delete(SCANNER_CACHE) : undefined,
  ])
}
