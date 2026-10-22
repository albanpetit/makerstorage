import { FormEvent, useEffect, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import type { ParameterFacet, ParameterFilter } from './types'

interface ParameterFilterDialogProps {
  facet: ParameterFacet | null
  current: ParameterFilter | undefined
  onOpenChange: (open: boolean) => void
  onApply: (filter: ParameterFilter | null) => void
}

// Filters the list on one parameter: a min/max range for number parameters
// (typed like part values: 10k, 100nF, 1/4W), a value list for text ones.
export function ParameterFilterDialog({ facet, current, onOpenChange, onApply }: ParameterFilterDialogProps) {
  const [min, setMin] = useState('')
  const [max, setMax] = useState('')
  const [values, setValues] = useState<string[]>([])

  useEffect(() => {
    if (!facet) return
    setMin(current?.min ?? '')
    setMax(current?.max ?? '')
    setValues(current?.values ?? [])
  }, [facet, current])

  if (!facet) return null

  const isNumber = facet.value_type === 'number'
  const empty = isNumber ? !min.trim() && !max.trim() : values.length === 0

  const submit = (e: FormEvent) => {
    e.preventDefault()
    onApply(empty ? null : {
      id: facet.id,
      name: facet.name,
      unit: facet.unit,
      value_type: facet.value_type,
      min: isNumber ? min.trim() || null : null,
      max: isNumber ? max.trim() || null : null,
      values: isNumber ? [] : values,
      invalid: false,
    })
  }

  const toggle = (value: string) =>
    setValues((list) => (list.includes(value) ? list.filter((v) => v !== value) : [ ...list, value ]))

  return (
    <Dialog open onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{facet.name}{facet.unit ? ` (${facet.unit})` : ''}</DialogTitle>
            <DialogDescription>
              {isNumber
                ? `${facet.count} part${facet.count !== 1 ? 's' : ''} from ${facet.min_display} to ${facet.max_display}. Leave a bound empty for no limit.`
                : `${facet.count} part${facet.count !== 1 ? 's' : ''} have a value.`}
            </DialogDescription>
          </DialogHeader>

          {isNumber ? (
            <div className="grid grid-cols-2 gap-3 py-4">
              <div className="space-y-2">
                <Label htmlFor="parameter-filter-min">Min</Label>
                <Input id="parameter-filter-min" className="font-mono" placeholder={facet.min_display ?? ''} value={min} onChange={(e) => setMin(e.target.value)} autoFocus />
              </div>
              <div className="space-y-2">
                <Label htmlFor="parameter-filter-max">Max</Label>
                <Input id="parameter-filter-max" className="font-mono" placeholder={facet.max_display ?? ''} value={max} onChange={(e) => setMax(e.target.value)} />
              </div>
            </div>
          ) : (
            <div className="max-h-64 space-y-2 overflow-y-auto py-4">
              {facet.values.map((option) => (
                <div key={option.value} className="flex items-center gap-2">
                  <Checkbox
                    id={`parameter-value-${option.value}`}
                    checked={values.includes(option.value)}
                    onCheckedChange={() => toggle(option.value)}
                  />
                  <Label htmlFor={`parameter-value-${option.value}`} className="cursor-pointer font-normal">
                    {option.label} <span className="text-muted-foreground">({option.count})</span>
                  </Label>
                </div>
              ))}
            </div>
          )}

          <DialogFooter>
            {current && (
              <Button type="button" variant="ghost" onClick={() => onApply(null)}>Clear</Button>
            )}
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button type="submit">Apply</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
