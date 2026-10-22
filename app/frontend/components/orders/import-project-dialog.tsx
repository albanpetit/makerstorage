import { FormEvent, useState } from 'react'
import { router } from '@inertiajs/react'

import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import type { Order, ProjectOption } from './types'
import { t, tn } from '@/lib/i18n'

interface ImportProjectDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  order: Order
  projects: ProjectOption[]
}

// Add a project's matched BOM lines to the order, at full or shortfall quantities.
export function ImportProjectDialog({ open, onOpenChange, order, projects }: ImportProjectDialogProps) {
  const [importProject, setImportProject] = useState('')
  const [importMode, setImportMode] = useState<'full' | 'shortfall'>('full')

  const submitImport = (e: FormEvent) => {
    e.preventDefault()
    if (!importProject) return
    router.post(
      `/orders/${order.id}/import_project`,
      { project_id: importProject, mode: importMode },
      {
        preserveScroll: true,
        onSuccess: () => {
          onOpenChange(false)
          setImportProject('')
        },
      }
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submitImport}>
          <DialogHeader>
            <DialogTitle>{t('Import from project')}</DialogTitle>
            <DialogDescription>
              {t('Add a project\'s matched BOM lines to this order. Unmatched lines are skipped.')}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>{t('Project')}</Label>
              <Select value={importProject} onValueChange={setImportProject}>
                <SelectTrigger>
                  <SelectValue placeholder={t('Select a project')} />
                </SelectTrigger>
                <SelectContent>
                  {projects.map((p) => (
                    <SelectItem key={p.id} value={String(p.id)}>
                      {p.name} ({tn('{count} line', '{count} lines', p.line_count)})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>{t('Quantities')}</Label>
              <Select value={importMode} onValueChange={(v) => setImportMode(v as 'full' | 'shortfall')}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="full">{t('Full BOM quantities')}</SelectItem>
                  <SelectItem value="shortfall">{t('Shortfall only (what stock can\'t cover)')}</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t('Cancel')}
            </Button>
            <Button type="submit" disabled={!importProject}>
              {t('Import lines')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
