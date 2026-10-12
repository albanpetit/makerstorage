import { useEffect, useMemo, useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { Upload } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import { csrfToken, parseCsvPreview, type ParsedImportRow } from './csv'

interface ImportPartsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  // Every MPN/SKU already in the inventory, loaded when the dialog opens.
  identifiers?: { mpns: string[]; skus: string[] }
}

// CSV import: previews the picked file client-side (new vs. updated rows),
// then submits it as a plain multipart form to PartsController#import.
export function ImportPartsDialog({ open, onOpenChange, identifiers }: ImportPartsDialogProps) {
  // The page only holds one page of parts, so the existing references are a
  // lazy prop, fetched once the dialog opens.
  useEffect(() => {
    if (open) router.reload({ only: [ 'part_identifiers' ] })
  }, [open])

  const [importRows, setImportRows] = useState<ParsedImportRow[] | null>(null)
  const [importError, setImportError] = useState('')
  const [importFileName, setImportFileName] = useState('')
  const importFormRef = useRef<HTMLFormElement>(null)

  const handleFilePicked = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setImportFileName(file.name)
    const reader = new FileReader()
    reader.onload = () => {
      const result = parseCsvPreview(String(reader.result || ''))
      if ('error' in result) {
        setImportError(result.error)
        setImportRows(null)
      } else {
        setImportError('')
        setImportRows(result.rows)
      }
    }
    reader.onerror = () => {
      setImportError('Could not read that file.')
      setImportRows(null)
    }
    reader.readAsText(file)
  }

  const isNewRow = useMemo(() => {
    const mpns = new Set(identifiers?.mpns)
    const skus = new Set(identifiers?.skus)
    return (r: ParsedImportRow) => !((r.mpn && mpns.has(r.mpn)) || (r.sku && skus.has(r.sku)))
  }, [identifiers])
  const importNewCount = importRows ? importRows.filter(isNewRow).length : 0
  const importUpdateCount = importRows ? importRows.length - importNewCount : 0

  const closeImport = () => {
    onOpenChange(false)
    setImportRows(null)
    setImportError('')
    setImportFileName('')
  }

  return (
    <Dialog open={open} onOpenChange={(next) => (next ? onOpenChange(true) : closeImport())}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Import inventory</DialogTitle>
          <DialogDescription>
            CSV file — columns are detected automatically (French and English headers both work).
          </DialogDescription>
        </DialogHeader>

        <form ref={importFormRef} action="/parts/import" method="post" encType="multipart/form-data">
          <input type="hidden" name="authenticity_token" value={csrfToken()} />
          <label className="flex cursor-pointer flex-col items-center gap-2 rounded-lg border border-dashed p-8 text-center hover:bg-accent">
            <Upload className="size-6 text-muted-foreground" />
            <span className="text-sm font-medium">Click to choose a file</span>
            <span className="text-xs text-muted-foreground">
              Headers: Name, Category, MPN, SKU, Value, Package, Location, Supplier, Quantity, Min Stock Threshold, Unit Price
            </span>
            <input type="file" name="file" accept=".csv,text/csv" className="hidden" onChange={handleFilePicked} />
          </label>

          {importError && (
            <p className="mt-3 text-sm text-destructive">{importError}</p>
          )}

          {importRows && !importError && (
            <div className="mt-4 space-y-3">
              <div className="text-sm text-muted-foreground">
                {importFileName} · {importRows.length} row{importRows.length !== 1 ? 's' : ''}
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div className="rounded-md bg-emerald-100 p-2 text-center dark:bg-emerald-950">
                  <div className="text-lg font-bold text-emerald-700 dark:text-emerald-400">{importNewCount}</div>
                  <div className="text-xs text-emerald-700 dark:text-emerald-400">New</div>
                </div>
                <div className="rounded-md bg-blue-100 p-2 text-center dark:bg-blue-950">
                  <div className="text-lg font-bold text-blue-700 dark:text-blue-400">{importUpdateCount}</div>
                  <div className="text-xs text-blue-700 dark:text-blue-400">Updated</div>
                </div>
              </div>
              <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border p-2">
                {importRows.slice(0, 8).map((r, i) => {
                  const isNew = isNewRow(r)
                  return (
                    <div key={i} className="flex items-center gap-2 text-sm">
                      <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${
                        isNew
                          ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400'
                          : 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400'
                      }`}>
                        {isNew ? 'NEW' : 'UPDATE'}
                      </span>
                      <span className="truncate">{r.name}</span>
                    </div>
                  )
                })}
              </div>
            </div>
          )}

          <DialogFooter className="mt-4">
            <Button type="button" variant="outline" onClick={closeImport}>
              Cancel
            </Button>
            <Button type="button" disabled={!importRows || !!importError} onClick={() => importFormRef.current?.requestSubmit()}>
              Confirm import
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
