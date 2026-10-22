import { useEffect, useState } from 'react'
import { t } from '@/lib/i18n'

// Shape of ParameterDefinitionsController#serialize_option.
export interface ParameterDefinitionOption {
  id: number
  name: string
  value_type: 'number' | 'text'
  unit: string | null
}

export interface ParameterCatalog {
  definitions: ParameterDefinitionOption[]
  // Category id => template parameter ids, parents' first.
  templates: Record<string, number[]>
}

const EMPTY: ParameterCatalog = { definitions: [], templates: {} }

// One request per page load, shared by every part form; refreshed after a
// parameter is created from the form.
let cached: Promise<ParameterCatalog> | null = null
const listeners = new Set<(catalog: ParameterCatalog) => void>()

function load(force = false) {
  if (!cached || force) {
    cached = fetch('/parameters', { headers: { Accept: 'application/json' } })
      .then((response) => (response.ok ? response.json() : EMPTY))
      .catch(() => EMPTY)
    cached.then((catalog) => listeners.forEach((listener) => listener(catalog)))
  }
  return cached
}

export function reloadParameterDefinitions() {
  return load(true)
}

// The organization's parameters and category templates, for the part form.
export function useParameterDefinitions(): ParameterCatalog {
  const [catalog, setCatalog] = useState<ParameterCatalog>(EMPTY)

  useEffect(() => {
    let active = true
    const listener = (next: ParameterCatalog) => active && setCatalog(next)
    listeners.add(listener)
    load().then(listener)
    return () => {
      active = false
      listeners.delete(listener)
    }
  }, [])

  return catalog
}

// Example input per unit, for placeholders.
export function parameterPlaceholder(definition: ParameterDefinitionOption) {
  if (definition.value_type === 'text') return 'e.g. X7R'
  const examples: Record<string, string> = {
    'Ω': 'e.g. 4k7, 10 kΩ',
    F: 'e.g. 100nF, 4u7',
    H: 'e.g. 10µH',
    V: 'e.g. 50V, 3V3',
    W: 'e.g. 1/4W, 125mW',
    A: 'e.g. 500mA',
    Hz: 'e.g. 16MHz',
    '%': 'e.g. 1%',
  }
  return examples[definition.unit ?? ''] ?? (definition.unit ? t('Number in {unit}', { unit: definition.unit }) : t('Number'))
}
