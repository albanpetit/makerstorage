import { useEffect, useState } from 'react'
import { router } from '@inertiajs/react'
import { Loader2 } from 'lucide-react'
import { toast } from 'sonner'

import type { PartImportStatus } from './types'
import { t } from '@/lib/i18n'

// How often a running import is polled.
const POLL_MS = 1500

// Progress of a CSV import running in the background (PartCsvImportJob):
// polls PartsController#import_status until it ends, then reports the outcome
// in a toast and reloads the list so the imported parts show up.
export function ImportProgress({ initial }: { initial: PartImportStatus | null }) {
  // Keyed by the import's id by the page, so a new import starts afresh.
  const [current, setCurrent] = useState(initial)

  const id = current?.id
  useEffect(() => {
    if (id == null) return
    let stopped = false
    let timer: number | undefined

    const poll = async () => {
      try {
        const response = await fetch(`/parts/imports/${id}`, { headers: { Accept: 'application/json' } })
        if (!response.ok) throw new Error(String(response.status))
        const status: PartImportStatus = await response.json()
        if (stopped) return
        if (status.status === 'done' || status.status === 'failed') {
          setCurrent(null)
          if (status.status === 'done') toast.success(status.message ?? '')
          else toast.error(status.message ?? '')
          router.reload({ except: [ 'part_import' ] })
          return
        }
        setCurrent(status)
      } catch {
        if (stopped) return
      }
      timer = window.setTimeout(poll, POLL_MS)
    }

    timer = window.setTimeout(poll, POLL_MS)
    return () => {
      stopped = true
      window.clearTimeout(timer)
    }
  }, [id])

  if (!current) return null

  const percent = current.total_rows > 0 ? Math.min(100, Math.round((current.processed_rows / current.total_rows) * 100)) : 0

  return (
    <div className="flex shrink-0 items-center gap-3 border-b bg-muted/40 px-4 py-2 text-sm sm:px-5" role="status">
      <Loader2 className="size-4 animate-spin text-muted-foreground" />
      <span className="truncate">
        {t('Importing {file}…', { file: current.filename })}
      </span>
      <div className="h-1.5 w-32 overflow-hidden rounded-full bg-muted">
        <div className="h-full bg-primary transition-all" style={{ width: `${percent}%` }} />
      </div>
      <span className="tabular-nums text-muted-foreground">
        {current.processed_rows} / {current.total_rows}
      </span>
    </div>
  )
}
