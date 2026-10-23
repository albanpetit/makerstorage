// Keeps the Scanner page usable without a network (see
// app/frontend/lib/offline-scanner). Registered by the Scanner page, which
// asks it to keep a copy of /scan and of the files the page loaded; when the
// server can't be reached, opening /scan serves that copy and the page answers
// scans from the data it keeps on the device. Every other request goes to the
// network as usual: nothing else works offline.
//
// Service workers only run on HTTPS (or localhost): plain-HTTP LAN installs
// still get offline scanning while the page stays open, but can't reopen it.

const CACHE = "makerstorage-scanner"
const SCANNER_PATH = "/scan"
// Built assets (vite_ruby's publicOutputDir per environment), icons, manifest.
const STATIC_PATH = /^\/(vite(-[a-z]+)?\/|icon[\w-]*\.(png|svg)$|manifest(\.json)?$)/

self.addEventListener("install", () => self.skipWaiting())

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener("message", (event) => {
  if (event.data?.type === "keep-scanner") {
    event.waitUntil(keepScanner(event.data.urls || []))
  }
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  if (request.method !== "GET") return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  if (request.mode === "navigate" && url.pathname === SCANNER_PATH) {
    event.respondWith(scannerPage(request))
  } else if (STATIC_PATH.test(url.pathname)) {
    event.respondWith(staticFile(request))
  }
})

// Stores a fresh copy of the Scanner page and the files it needs, and drops
// files of older builds. A signed-out session is redirected to the sign-in
// page: the copy is then deleted, not replaced.
async function keepScanner(urls) {
  const cache = await caches.open(CACHE)
  const page = await fetch(SCANNER_PATH, { credentials: "same-origin", cache: "no-store" }).catch(() => null)
  if (!page) return
  if (!isScannerPage(page)) {
    await caches.delete(CACHE)
    return
  }

  const wanted = new Set(urls.filter((href) => {
    const url = new URL(href, self.location.origin)
    return url.origin === self.location.origin && STATIC_PATH.test(url.pathname)
  }).map((href) => new URL(href, self.location.origin).href))

  await cache.put(SCANNER_PATH, page)
  await Promise.all([...wanted].map(async (href) => {
    if (await cache.match(href)) return
    const response = await fetch(href).catch(() => null)
    if (response?.ok) await cache.put(href, response)
  }))

  for (const request of await cache.keys()) {
    const path = new URL(request.url).pathname
    if (path !== SCANNER_PATH && !wanted.has(request.url)) await cache.delete(request)
  }
}

function isScannerPage(response) {
  return response.ok && !response.redirected && (response.headers.get("content-type") || "").includes("text/html")
}

// Network first; the kept copy when the server can't be reached.
async function scannerPage(request) {
  try {
    const response = await fetch(request)
    if (response.redirected) {
      // Signed out: don't serve this account's copy to whoever signs in next.
      await caches.delete(CACHE)
    }
    return response
  } catch (error) {
    const kept = await caches.match(SCANNER_PATH, { cacheName: CACHE })
    if (kept) return kept
    throw error
  }
}

// Network first too (development assets aren't fingerprinted); files the
// Scanner page kept are refreshed as they're fetched.
async function staticFile(request) {
  try {
    const response = await fetch(request)
    if (response.ok) {
      const cache = await caches.open(CACHE)
      if (await cache.match(request)) await cache.put(request, response.clone())
    }
    return response
  } catch (error) {
    const kept = await caches.match(request, { cacheName: CACHE })
    if (kept) return kept
    throw error
  }
}
