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
            <DialogTitle>Import from project</DialogTitle>
            <DialogDescription>
              Add a project's matched BOM lines to this order. Unmatched lines are skipped.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Project</Label>
              <Select value={importProject} onValueChange={setImportProject}>
                <SelectTrigger>
                  <SelectValue placeholder="Select a project" />
                </SelectTrigger>
                <SelectContent>
                  {projects.map((p) => (
                    <SelectItem key={p.id} value={String(p.id)}>
                      {p.name} ({p.line_count} line{p.line_count !== 1 ? 's' : ''})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Quantities</Label>
              <Select value={importMode} onValueChange={(v) => setImportMode(v as 'full' | 'shortfall')}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="full">Full BOM quantities</SelectItem>
                  <SelectItem value="shortfall">Shortfall only (what stock can't cover)</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={!importProject}>
              Import lines
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
