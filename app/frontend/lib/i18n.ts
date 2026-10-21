import { Fragment, createElement, type ReactNode } from 'react'

import fr from '@/locales/fr.json'

// UI translations. The English text is the key: `t('Add part')` returns the
// French text when the current locale is French and has an entry for it, and
// the English text otherwise, so an untranslated string still reads fine.
//
//   t('Delete {name}?', { name: part.name })
//   tn('{count} part', '{count} parts', parts.length)
//   tx('{name} will be removed.', { name: <strong>{part.name}</strong> })
//
// Translations live in `app/frontend/locales/fr.json`, keyed by the English
// text (for `tn`, by the plural English form, with `one`/`other` variants).
// `bin/rails i18n:frontend` lists the keys used in the code that fr.json lacks.

export const LOCALES = ['en', 'fr'] as const
export type Locale = (typeof LOCALES)[number]

export const LOCALE_NAMES: Record<Locale, string> = { en: 'English', fr: 'Français' }

type Plural = { one?: string; other: string }
type Catalog = Record<string, string | Plural>

const CATALOGS: Record<Locale, Catalog> = { en: {}, fr: fr as Catalog }

let current: Locale = 'en'

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (LOCALES as readonly string[]).includes(value)
}

// Called from the Inertia entrypoint with the `locale` prop of every page the
// server renders, before the page itself renders.
export function setLocale(locale: unknown) {
  current = isLocale(locale) ? locale : 'en'
  if (typeof document !== 'undefined') document.documentElement.lang = current
}

export function getLocale(): Locale {
  return current
}

// BCP 47 tag for Intl / toLocaleString, so numbers and dates follow the UI
// language rather than the browser's.
export function intlLocale(): string {
  return current === 'fr' ? 'fr-FR' : 'en-US'
}

function interpolate(text: string, vars?: Record<string, string | number>) {
  if (!vars) return text
  return text.replace(/\{(\w+)\}/g, (match, name: string) =>
    name in vars ? formatValue(vars[name]) : match,
  )
}

function formatValue(value: string | number) {
  return typeof value === 'number' ? value.toLocaleString(intlLocale()) : value
}

function lookup(text: string) {
  const entry = CATALOGS[current][text]
  return typeof entry === 'string' ? entry : entry?.other ?? text
}

export function t(text: string, vars?: Record<string, string | number>): string {
  return interpolate(lookup(text), vars)
}

// Like `t`, for a sentence with elements in it (a bold name, a link): the
// placeholders take React nodes, so translators can move them around.
export function tx(text: string, vars: Record<string, ReactNode>): ReactNode {
  return interpolateNodes(lookup(text), vars)
}

function interpolateNodes(text: string, vars: Record<string, ReactNode>): ReactNode {
  const nodes = text.split(/(\{\w+\})/).map((piece) => {
    const name = /^\{(\w+)\}$/.exec(piece)?.[1]
    if (!name || !(name in vars)) return piece
    const value = vars[name]
    return typeof value === 'number' ? formatValue(value) : value
  })
  return createElement(Fragment, null, ...nodes)
}

// Plural form picked by the locale's rules (French treats 0 as singular).
// `count` is available as `{count}` in both forms.
export function tn(one: string, other: string, count: number, vars?: Record<string, string | number>): string {
  const allVars = { count, ...vars }
  const entry = CATALOGS[current][other]
  const rule = new Intl.PluralRules(intlLocale()).select(count)
  if (entry && typeof entry === 'object') {
    return interpolate(rule === 'one' ? entry.one ?? entry.other : entry.other, allVars)
  }
  if (typeof entry === 'string') return interpolate(entry, allVars)
  return interpolate(rule === 'one' ? one : other, allVars)
}

// `tn` with React nodes in the placeholders (see `tx`).
export function txn(one: string, other: string, count: number, vars: Record<string, ReactNode>): ReactNode {
  const entry = CATALOGS[current][other]
  const rule = new Intl.PluralRules(intlLocale()).select(count)
  let text = rule === 'one' ? one : other
  if (entry && typeof entry === 'object') text = rule === 'one' ? entry.one ?? entry.other : entry.other
  else if (typeof entry === 'string') text = entry
  return interpolateNodes(text, { count: formatValue(count), ...vars })
}
