import type { Dispatch, SetStateAction } from 'react'
import { ArrowRightLeft } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldLabel } from '@/components/ui/field'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import type { MoveDialogState } from './types'
import { t, tn } from '@/lib/i18n'
import { formatQuantity, isDecimalUnit, quantityStep } from '@/lib/quantity'

// A typed move quantity kept between the smallest step and what the zone
// holds: whole pieces, a measure to the thousandth.
function clampMove(value: number, max: number, unit: string) {
  if (!isDecimalUnit(unit)) return Math.max(1, Math.min(max, Math.floor(value)))
  return Math.max(0.001, Math.min(max, Math.round(value * 1000) / 1000))
}

interface MoveStockDialogProps {
  moveDialog: MoveDialogState | null
  setMoveDialog: Dispatch<SetStateAction<MoveDialogState | null>>
  zones: StorageLocationOption[]
  zoneName: (id: number) => string | undefined
  valid: boolean
  onSubmit: () => void
}

// Quantities to move per component, and the destination (fixed after a drop,
// picked from a list for the bulk "Move to…" button).
export function MoveStockDialog({ moveDialog, setMoveDialog, zones, zoneName, valid, onSubmit }: MoveStockDialogProps) {
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
            {tn('Move component', 'Move {count} components', moveDialog?.rows.length ?? 0)}
          </DialogTitle>
        </DialogHeader>
        {moveDialog && (
          <div className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>{t('Destination zone')}</Label>
              </FieldLabel>
              <FieldContent>
                {moveDialog.mode === 'select' ? (
                  <StorageLocationSelect
                    locations={zones}
                    value={moveDialog.toId != null ? String(moveDialog.toId) : ''}
                    onValueChange={(value) => setMoveDialog((prev) => prev && { ...prev, toId: Number(value) })}
                    placeholder={t('Choose a zone…')}
                    exclude={[moveDialog.fromId]}
                  />
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
                      min={isDecimalUnit(r.unit) ? 0 : 1}
                      max={r.max}
                      step={quantityStep(r.unit)}
                      value={r.quantity}
                      onChange={(e) => setMoveRowQuantity(r.partId, clampMove(Number(e.target.value) || 0, r.max, r.unit))}
                      className="h-8 w-20 text-right font-mono"
                      aria-label={t('Quantity to move for {reference}', { reference: r.reference })}
                    />
                    <span className="w-16 text-xs text-muted-foreground">/ {formatQuantity(r.max, r.unit)}</span>
                  </div>
                </div>
              ))}
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setMoveDialog(null)}>{t('Cancel')}</Button>
              <Button type="button" onClick={onSubmit} disabled={!valid}>
                <ArrowRightLeft className="size-4" />
                {t('Move')}
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
