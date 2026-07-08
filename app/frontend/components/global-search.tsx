import { router } from '@inertiajs/react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, Package, Box, Loader2 } from 'lucide-react'

import { Input } from '@/components/ui/input'

interface PartResult {
  id: number
  reference: string
  name: string
  category: string | null
}

interface ZoneResult {
  id: number
  name: string
  path: string
  location_type: string
}

interface SearchResults {
  parts: PartResult[]
  zones: ZoneResult[]
}

const EMPTY: SearchResults = { parts: [], zones: [] }
const MIN_QUERY_LENGTH = 2

/**
 * "Search everywhere" box for the dashboard header. Debounced XHR against the
 * JSON `/search` endpoint, with a grouped Components / Zones results dropdown.
 */
export function GlobalSearch() {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchResults>(EMPTY)
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)

  const trimmed = query.trim()

  useEffect(() => {
    if (trimmed.length < MIN_QUERY_LENGTH) {
      setResults(EMPTY)
      setLoading(false)
      return
    }

    const controller = new AbortController()
    setLoading(true)
    const timer = setTimeout(() => {
      fetch(`/search?q=${encodeURIComponent(trimmed)}`, {
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      })
        .then((res) => (res.ok ? res.json() : EMPTY))
        .then((data: SearchResults) => setResults(data))
        .catch(() => { /* aborted or failed — leave prior results */ })
        .finally(() => setLoading(false))
    }, 200)

    return () => {
      controller.abort()
      clearTimeout(timer)
    }
  }, [trimmed])

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [])

  const hasResults = results.parts.length > 0 || results.zones.length > 0
  const showDropdown = open && trimmed.length >= MIN_QUERY_LENGTH

  const go = (href: string) => {
    setOpen(false)
    setQuery('')
    router.visit(href)
  }

  const emptyLabel = useMemo(() => (loading ? 'Searching…' : 'No matches'), [loading])

  return (
    <div ref={containerRef} className="relative w-full max-w-sm">
      <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
      {loading && <Loader2 className="absolute top-1/2 right-3 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />}
      <Input
        value={query}
        onChange={(e) => { setQuery(e.target.value); setOpen(true) }}
        onFocus={() => setOpen(true)}
        onKeyDown={(e) => { if (e.key === 'Escape') setOpen(false) }}
        placeholder="Search a component or zone…"
        className="pl-9"
        aria-label="Search everywhere"
      />

      {showDropdown && (
        <div className="absolute z-50 mt-1.5 w-full overflow-hidden rounded-md border bg-popover text-popover-foreground shadow-md">
          {!hasResults ? (
            <div className="px-3 py-4 text-center text-sm text-muted-foreground">{emptyLabel}</div>
          ) : (
            <div className="max-h-80 overflow-y-auto py-1">
              {results.parts.length > 0 && (
                <div>
                  <div className="px-3 py-1.5 text-xs font-semibold text-muted-foreground">Components</div>
                  {results.parts.map((part) => (
                    <button
                      key={`p-${part.id}`}
                      type="button"
                      onClick={() => go(`/parts/${part.id}`)}
                      className="flex w-full items-center gap-2.5 px-3 py-2 text-left hover:bg-accent"
                    >
                      <Package className="size-4 shrink-0 text-muted-foreground" />
                      <div className="min-w-0 flex-1">
                        <div className="truncate font-mono text-sm font-semibold">{part.reference}</div>
                        <div className="truncate text-xs text-muted-foreground">{part.name}</div>
                      </div>
                      {part.category && <span className="shrink-0 text-xs text-muted-foreground">{part.category}</span>}
                    </button>
                  ))}
                </div>
              )}
              {results.zones.length > 0 && (
                <div>
                  <div className="px-3 py-1.5 text-xs font-semibold text-muted-foreground">Zones</div>
                  {results.zones.map((zone) => (
                    <button
                      key={`z-${zone.id}`}
                      type="button"
                      onClick={() => go('/storage_locations')}
                      className="flex w-full items-center gap-2.5 px-3 py-2 text-left hover:bg-accent"
                    >
                      <Box className="size-4 shrink-0 text-muted-foreground" />
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm font-medium">{zone.name}</div>
                        <div className="truncate text-xs text-muted-foreground">{zone.path}</div>
                      </div>
                      <span className="shrink-0 text-xs text-muted-foreground capitalize">{zone.location_type}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
