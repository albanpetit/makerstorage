import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

// Preset colors offered for tags and categories. The leading `null` is "no
// color"; every other value is a #RRGGBB hex the Tag and Category models accept.
const PRESET_COLORS: Array<{ value: string | null; className: string }> = [
  { value: null, className: 'bg-muted' },
  { value: '#EF4444', className: 'bg-red-500' },
  { value: '#F97316', className: 'bg-orange-500' },
  { value: '#EAB308', className: 'bg-yellow-500' },
  { value: '#22C55E', className: 'bg-green-500' },
  { value: '#3B82F6', className: 'bg-blue-500' },
  { value: '#8B5CF6', className: 'bg-violet-500' },
  { value: '#EC4899', className: 'bg-pink-500' },
  { value: '#64748B', className: 'bg-slate-500' },
]

interface ColorSwatchesProps {
  value: string | null
  onChange: (value: string | null) => void
}

// Row of round color swatches; the selected one is ringed.
export function ColorSwatches({ value, onChange }: ColorSwatchesProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {PRESET_COLORS.map((preset) => (
        <Button
          key={preset.value ?? 'none'}
          type="button"
          variant="ghost"
          size="icon"
          onClick={() => onChange(preset.value)}
          aria-label={preset.value ?? 'No color'}
          aria-pressed={value === preset.value}
          className={cn(
            'size-6 rounded-full p-0 hover:bg-transparent dark:hover:bg-transparent',
            value === preset.value && 'ring-2 ring-ring ring-offset-2 ring-offset-background'
          )}
        >
          <span className={cn('size-6 rounded-full border', preset.className)} />
        </Button>
      ))}
    </div>
  )
}
