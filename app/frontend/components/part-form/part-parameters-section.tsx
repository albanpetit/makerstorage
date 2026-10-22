import { FormEvent, useMemo, useState } from 'react'
import { ChevronRight, X } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { FieldError } from '@/components/ui/field'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  parameterPlaceholder,
  reloadParameterDefinitions,
  useParameterDefinitions,
  type ParameterDefinitionOption,
} from '@/components/parameters/use-parameter-definitions'

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

interface PartParametersSectionProps {
  categoryId: string
  // Parameter definition id => value; null = removed in this form.
  values: Record<string, string | null>
  onChange: (values: Record<string, string | null>) => void
  error?: string
}

// The part form's parameters: a row per parameter of the category's template
// (inherited from its parents) and per other parameter the part has, plus a
// picker to add any other parameter or create one.
export function PartParametersSection({ categoryId, values, onChange, error }: PartParametersSectionProps) {
  const { definitions, templates } = useParameterDefinitions()
  const [open, setOpen] = useState(true)
  const [createOpen, setCreateOpen] = useState(false)
  const [newName, setNewName] = useState('')
  const [newType, setNewType] = useState<'number' | 'text'>('number')
  const [newUnit, setNewUnit] = useState('')
  const [createError, setCreateError] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)

  const byId = useMemo(() => new Map(definitions.map((d) => [d.id, d])), [definitions])
  const template = templates[categoryId] ?? []

  const rows = useMemo(() => {
    const ids = [ ...template ]
    Object.entries(values).forEach(([id, value]) => {
      if (value !== null && !ids.includes(Number(id))) ids.push(Number(id))
    })
    return ids.flatMap((id) => byId.get(id) ?? [])
  }, [template, values, byId])

  const shown = new Set(rows.map((d) => d.id))
  const options: ComboboxOption[] = definitions
    .filter((d) => !shown.has(d.id))
    .map((d) => ({ value: String(d.id), label: d.name, hint: d.unit ?? (d.value_type === 'text' ? 'text' : undefined) }))

  const setValue = (id: number, value: string | null) => onChange({ ...values, [id]: value })

  const startCreate = (query: string) => {
    setNewName(query)
    setNewType('number')
    setNewUnit('')
    setCreateError(null)
    setCreateOpen(true)
  }

  const create = async (e: FormEvent) => {
    e.preventDefault()
    e.stopPropagation()
    const name = newName.trim()
    if (!name) {
      setCreateError('Name is required.')
      return
    }
    const existing = definitions.find((d) => d.name.toLowerCase() === name.toLowerCase())
    if (existing) {
      setValue(existing.id, values[existing.id] ?? '')
      setCreateOpen(false)
      return
    }

    setProcessing(true)
    setCreateError(null)
    try {
      const response = await fetch('/parameters', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
        body: JSON.stringify({ parameter_definition: { name, value_type: newType, unit: newType === 'number' ? newUnit : null } }),
      })
      const data = await response.json().catch(() => ({}))
      if (response.ok && data.definition) {
        await reloadParameterDefinitions()
        setValue((data.definition as ParameterDefinitionOption).id, '')
        setCreateOpen(false)
      } else {
        const errors = (data.errors ?? {}) as Record<string, string>
        setCreateError(errors.name ?? Object.values(errors)[0] ?? 'Could not create the parameter.')
      }
    } catch {
      setCreateError('Could not create the parameter.')
    } finally {
      setProcessing(false)
    }
  }

  const filled = rows.filter((d) => values[d.id]).map((d) => d.name)
  const description = filled.length > 0
    ? filled.join(', ')
    : rows.length > 0
      ? `Suggested: ${rows.map((d) => d.name).join(', ')}`
      : 'Technical values to filter on (resistance, capacitance…)'

  return (
    <div className="rounded-lg border">
      <Button
        type="button"
        variant="ghost"
        onClick={() => setOpen((v) => !v)}
        className="flex h-auto w-full justify-start gap-2 px-4 py-3 text-left font-normal whitespace-normal has-[>svg]:px-4 hover:bg-transparent dark:hover:bg-transparent"
      >
        <ChevronRight className={`size-4 shrink-0 text-muted-foreground transition-transform ${open || error ? 'rotate-90' : ''}`} />
        <span className="flex-1">
          <span className="block text-sm font-medium">Parameters</span>
          <span className="block text-xs text-muted-foreground">{description}</span>
        </span>
      </Button>
      {(open || error) && (
        <div className="space-y-3 border-t px-4 py-4">
          {rows.length > 0 && (
            <div className="grid grid-cols-1 gap-3 @2xl:grid-cols-2">
              {rows.map((definition) => {
                const inputId = `part-parameter-${definition.id}`
                const removable = !template.includes(definition.id)
                return (
                  <div key={definition.id} className="flex items-center gap-2">
                    <Label htmlFor={inputId} className="w-32 shrink-0 truncate text-sm" title={definition.name}>
                      {definition.name}
                    </Label>
                    <Input
                      id={inputId}
                      value={values[definition.id] ?? ''}
                      placeholder={parameterPlaceholder(definition)}
                      onChange={(e) => setValue(definition.id, e.target.value)}
                      className="font-mono"
                    />
                    <span className="w-8 shrink-0 text-xs text-muted-foreground">{definition.unit}</span>
                    {removable ? (
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        className="size-8 shrink-0"
                        onClick={() => setValue(definition.id, null)}
                        aria-label={`Remove ${definition.name}`}
                      >
                        <X className="size-4" />
                      </Button>
                    ) : (
                      <span className="size-8 shrink-0" />
                    )}
                  </div>
                )
              })}
            </div>
          )}
          {error && <FieldError>{error}</FieldError>}
          <div className="flex flex-wrap items-center gap-2">
            <Combobox
              options={options}
              value=""
              onValueChange={(value) => value && setValue(Number(value), values[Number(value)] ?? '')}
              placeholder="Add a parameter…"
              searchPlaceholder="Search parameters…"
              emptyText={definitions.length === 0 ? 'No parameter yet.' : 'No other parameter.'}
              className="w-56"
              onCreate={startCreate}
              createLabel={(query) => (query ? `Create parameter "${query}"` : 'New parameter…')}
            />
            <span className="text-xs text-muted-foreground">
              Type values as usual: 4k7, 100nF, 1/4W, 3V3. Categories propose their parameters (Parameters page).
            </span>
          </div>
        </div>
      )}

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="sm:max-w-sm">
          {/* Inside the part form: keep this submit from bubbling up to it. */}
          <form onSubmit={create}>
            <DialogHeader>
              <DialogTitle>New parameter</DialogTitle>
              <DialogDescription>Available on every part of the organization.</DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="new-parameter-name">Name</Label>
                <Input id="new-parameter-name" value={newName} onChange={(e) => setNewName(e.target.value)} autoFocus />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label>Type</Label>
                  <Select value={newType} onValueChange={(value) => setNewType(value as 'number' | 'text')}>
                    <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="number">Number</SelectItem>
                      <SelectItem value="text">Text</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {newType === 'number' && (
                  <div className="space-y-2">
                    <Label htmlFor="new-parameter-unit">Unit</Label>
                    <Input id="new-parameter-unit" placeholder="e.g. V, Ω, dB" value={newUnit} onChange={(e) => setNewUnit(e.target.value)} />
                  </div>
                )}
              </div>
              {createError && <FieldError>{createError}</FieldError>}
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={processing}>Create</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
