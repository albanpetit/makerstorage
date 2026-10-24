import { ComponentProps } from 'react'
import { Plus } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { t } from '@/lib/i18n'
import { cleanQuantityInput, formatQuantity, isDecimalUnit, parseQuantity, sumQuantities, unitSymbol } from '@/lib/quantity'

type QuantityInputProps = Omit<ComponentProps<typeof Input>, 'value' | 'onChange' | 'type'> & {
  value: string
  onValueChange: (value: string) => void
  // The part's unit: a measure takes decimals ("2,5") and shows its symbol.
  unit?: string | null
  // How much one pack holds (Part#pack_size): offers "+1 pack" to add it.
  packSize?: number | null
}

// A quantity field in a part's unit: whole numbers for pieces, decimals for a
// measure, with the unit's symbol beside it and an optional "+1 pack" button
// (a 1 kg spool entered as 1000 g).
export function QuantityInput({ value, onValueChange, unit, packSize, className, ...props }: QuantityInputProps) {
  const symbol = unitSymbol(unit)
  const addPack = () => onValueChange(String(sumQuantities([ parseQuantity(value) ?? 0, packSize ?? 0 ])))

  return (
    <div className="space-y-1.5">
      <div className="flex items-center gap-2">
        <Input
          inputMode={isDecimalUnit(unit) ? 'decimal' : 'numeric'}
          placeholder="0"
          {...props}
          className={className}
          value={value}
          onChange={(e) => onValueChange(cleanQuantityInput(e.target.value, unit))}
        />
        {symbol && <span className="shrink-0 text-sm text-muted-foreground">{symbol}</span>}
      </div>
      {packSize != null && packSize > 0 && (
        <Button type="button" variant="outline" size="sm" className="h-7 px-2 text-xs" onClick={addPack} disabled={props.disabled}>
          <Plus className="size-3" />
          {t('1 pack ({quantity})', { quantity: formatQuantity(packSize, unit) })}
        </Button>
      )}
    </div>
  )
}
