import type { Dispatch, SetStateAction } from 'react'
import { ArrowRightLeft } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldLabel } from '@/components/ui/field'
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
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import type { MoveDialogState } from './types'

interface MoveStockDialogProps {
  moveDialog: MoveDialogState | null
  setMoveDialog: Dispatch<SetStateAction<MoveDialogState | null>>
  zoneOptions: { id: number; label: string }[]
  zoneName: (id: number) => string | undefined
  valid: boolean
  onSubmit: () => void
}

// Quantities to move per component, and the destination (fixed after a drop,
// picked from a list for the bulk "Move to…" button).
export function MoveStockDialog({ moveDialog, setMoveDialog, zoneOptions, zoneName, valid, onSubmit }: MoveStockDialogProps) {
  function setMoveRowQuantity(partId: number, quantity: number) {
    setMoveDialog((prev) => (prev
      ? { ...prev, rows: prev.rows.map((r) => (r.partId === partId ? { ...r, quantity } : r)) }
      : prev))
  }

  return (
    <Dialog open={moveDialog !== null} onOpenChange={(open) => !open && setMoveDialog(null)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            Move {moveDialog?.rows.length === 1 ? 'component' : `${moveDialog?.rows.length} components`}
          </DialogTitle>
        </DialogHeader>
        {moveDialog && (
          <div className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>Destination zone</Label>
              </FieldLabel>
              <FieldContent>
                {moveDialog.mode === 'select' ? (
                  <Select
                    value={moveDialog.toId != null ? String(moveDialog.toId) : ''}
                    onValueChange={(value) => setMoveDialog((prev) => prev && { ...prev, toId: Number(value) })}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Choose a zone…" />
                    </SelectTrigger>
                    <SelectContent>
                      {zoneOptions
                        .filter((o) => o.id !== moveDialog.fromId)
                        .map((o) => (
                          <SelectItem key={o.id} value={String(o.id)}>{o.label}</SelectItem>
                        ))}
                    </SelectContent>
                  </Select>
                ) : (
                  <div className="rounded-md border bg-muted px-3 py-2 text-sm font-medium">
                    {moveDialog.toId != null ? zoneName(moveDialog.toId) : ''}
                  </div>
                )}
              </FieldContent>
            </Field>

            <div className="overflow-hidden rounded-lg border divide-y">
              {moveDialog.rows.map((r) => (
                <div key={r.partId} className="flex items-center gap-3 px-3 py-2">
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-mono text-sm font-semibold">{r.reference}</div>
                    <div className="truncate text-xs text-muted-foreground">{r.name}</div>
                  </div>
                  <div className="flex items-center gap-1.5">
                    <Input
                      type="number"
                      min={1}
                      max={r.max}
                      value={r.quantity}
                      onChange={(e) => setMoveRowQuantity(r.partId, Math.max(1, Math.min(r.max, Math.floor(Number(e.target.value) || 0))))}
                      className="h-8 w-20 text-right font-mono"
                      aria-label={`Quantity to move for ${r.reference}`}
                    />
                    <span className="w-14 text-xs text-muted-foreground">/ {r.max}</span>
                  </div>
                </div>
              ))}
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setMoveDialog(null)}>Cancel</Button>
              <Button type="button" onClick={onSubmit} disabled={!valid}>
                <ArrowRightLeft className="size-4" />
                Move
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
