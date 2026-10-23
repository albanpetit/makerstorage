import { Plus, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { t } from '@/lib/i18n'
import { PendingPriceBreak } from './types'

interface PriceBreaksEditorProps {
  value: PendingPriceBreak[]
  onChange: (rows: PendingPriceBreak[]) => void
}

// A supplier link's quantity price breaks ("from 100: 0.05 each"), edited as
// rows. Catalog lookups fill them; orders pick the break for their quantity.
export function PriceBreaksEditor({ value, onChange }: PriceBreaksEditorProps) {
  const update = (index: number, patch: Partial<PendingPriceBreak>) =>
    onChange(value.map((row, i) => (i === index ? { ...row, ...patch } : row)))

  return (
    <div className="space-y-2">
      {value.length > 0 && (
        <div className="grid grid-cols-[1fr_1fr_auto] items-center gap-2 text-xs text-muted-foreground">
          <span>{t('From quantity')}</span>
          <span>{t('Unit price')}</span>
          <span className="w-9" />
        </div>
      )}
      {value.map((row, index) => (
        <div key={index} className="grid grid-cols-[1fr_1fr_auto] items-center gap-2">
          <Input
            inputMode="numeric"
            aria-label={t('From quantity')}
            placeholder="100"
            value={row.quantity}
            onChange={(e) => update(index, { quantity: e.target.value.replace(/[^0-9]/g, '') })}
          />
          <Input
            type="number"
            step="0.0001"
            min="0"
            aria-label={t('Unit price')}
            placeholder="0.05"
            value={row.unit_price}
            onChange={(e) => update(index, { unit_price: e.target.value })}
          />
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={() => onChange(value.filter((_, i) => i !== index))}
            title={t('Remove price break')}
          >
            <Trash2 className="size-4 text-destructive" />
          </Button>
        </div>
      ))}
      <Button type="button" size="sm" variant="outline" onClick={() => onChange([...value, { quantity: '', unit_price: '' }])}>
        <Plus className="size-4" />
        {t('Add price break')}
      </Button>
    </div>
  )
}
