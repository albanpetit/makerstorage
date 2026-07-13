import { useState } from 'react'
import { Search, Loader2, FileText, Image as ImageIcon } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'

// A normalized catalog match returned by POST /parts/lookup.
export interface LookupResult {
  name: string | null
  mpn: string | null
  manufacturer: string | null
  description: string | null
  value: string | null
  package_type: string | null
  tolerance: string | null
  voltage_rating: string | null
  power_rating: string | null
  unit_price: string | null
  rohs_compliant: boolean
  datasheet_url: string | null
  image_url: string | null
  product_url: string | null
  supplier_sku: string | null
  provider: string
}

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

interface SupplierLookupProps {
  // Seed the search box (e.g. the part's existing MPN when editing).
  defaultQuery?: string
  // Called with the chosen match — the parent prefills its form from it.
  onApply: (result: LookupResult) => void
  // Whether a datasheet/image is currently queued for attachment, for the badges.
  attached?: { datasheet: boolean; image: boolean }
}

// Search an external supplier catalog (Mouser) by manufacturer part number and
// let the user pick a match. Owns the query/results state; the parent owns what
// happens to the chosen result via `onApply`.
export function SupplierLookup({ defaultQuery = '', onApply, attached }: SupplierLookupProps) {
  const [query, setQuery] = useState(defaultQuery)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [results, setResults] = useState<LookupResult[] | null>(null)

  const apply = (result: LookupResult) => {
    onApply(result)
    setResults(null)
    setError(null)
  }

  const runLookup = async () => {
    const mpn = query.trim()
    if (!mpn) return
    setLoading(true)
    setError(null)
    setResults(null)
    try {
      const res = await fetch('/parts/lookup', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        credentials: 'same-origin',
        body: JSON.stringify({ mpn }),
      })
      const json = await res.json()
      if (!res.ok) {
        setError(json.error ?? 'Lookup failed.')
        return
      }
      const found: LookupResult[] = json.results ?? []
      if (found.length === 0) {
        setError(`No matches found for "${mpn}".`)
      } else if (found.length === 1) {
        apply(found[0])
      } else {
        setResults(found)
      }
    } catch {
      setError('Could not reach the server. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="rounded-lg border border-dashed bg-muted/40 p-4">
      <Label className="text-sm font-medium">Look up from Mouser</Label>
      <p className="mb-2.5 text-xs text-muted-foreground">
        Enter a manufacturer part number to auto-fill details, datasheet and image.
      </p>
      <div className="flex gap-2">
        <Input
          placeholder="e.g. RC0805FR-0710KL"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              runLookup()
            }
          }}
        />
        <Button type="button" variant="secondary" onClick={runLookup} disabled={loading || !query.trim()}>
          {loading ? <Loader2 className="size-4 animate-spin" /> : <Search className="size-4" />}
          Fetch
        </Button>
      </div>

      {error && <p className="mt-2 text-sm text-destructive">{error}</p>}

      {/* Multiple matches — let the user pick one */}
      {results && results.length > 0 && (
        <div className="mt-3 space-y-2">
          <p className="text-xs font-medium text-muted-foreground">{results.length} matches — select one:</p>
          <div className="max-h-64 space-y-2 overflow-y-auto">
            {results.map((result, index) => (
              <button
                key={`${result.supplier_sku ?? result.mpn}-${index}`}
                type="button"
                onClick={() => apply(result)}
                className="flex w-full items-start gap-3 rounded-md border bg-background p-2.5 text-left transition-colors hover:border-primary hover:bg-accent"
              >
                {result.image_url && (
                  <img
                    src={result.image_url}
                    alt=""
                    className="size-10 shrink-0 rounded border bg-white object-contain"
                    loading="lazy"
                  />
                )}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="truncate text-sm font-medium">{result.mpn ?? result.name}</span>
                    {result.manufacturer && (
                      <Badge variant="secondary" className="shrink-0 text-[10px]">{result.manufacturer}</Badge>
                    )}
                  </div>
                  {result.description && <p className="truncate text-xs text-muted-foreground">{result.description}</p>}
                  <div className="mt-0.5 flex flex-wrap gap-x-3 gap-y-0.5 text-[11px] text-muted-foreground">
                    {result.package_type && <span>{result.package_type}</span>}
                    {result.value && <span>{result.value}</span>}
                    {result.unit_price && <span className="font-mono">${parseFloat(result.unit_price).toFixed(2)}</span>}
                  </div>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* What will be attached once a match is applied */}
      {attached && (attached.datasheet || attached.image) && (
        <div className="mt-3 flex flex-wrap gap-2">
          {attached.datasheet && (
            <Badge variant="secondary" className="gap-1">
              <FileText className="size-3" /> Datasheet will be attached
            </Badge>
          )}
          {attached.image && (
            <Badge variant="secondary" className="gap-1">
              <ImageIcon className="size-3" /> Image will be attached
            </Badge>
          )}
        </div>
      )}
    </div>
  )
}
