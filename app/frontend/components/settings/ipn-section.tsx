import { FormEvent, useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { Hash, Info, TrendingUp, Shuffle, Boxes, Pencil, Check, TriangleAlert, PackageOpen } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'

import type { IpnForm, IpnMode, OrganizationSettings } from './types'

const SEPARATOR_LABELS: Record<string, string> = {
  '-': '-',
  '.': '.',
  _: '_',
  '/': '/',
  '': 'None',
}

const DIGIT_OPTIONS = [3, 4, 5, 6, 7, 8]

const IPN_MODES = [
  { value: 'incremental', label: 'Incremental', icon: TrendingUp, description: 'Auto-incrementing sequential counter. Ordered, predictable references.' },
  { value: 'random', label: 'Random', icon: Shuffle, description: 'Unique non-sequential draw. Avoids revealing how many parts exist.' },
  { value: 'category_sequence', label: 'Category + sequence', icon: Boxes, description: 'An independent counter per category (RES-00001, CAP-00001…).' },
  { value: 'manual', label: 'Manual', icon: Pencil, description: 'Free entry by the operator, with a suggested value.' },
  { value: 'box_bag', label: 'Box & bag', icon: PackageOpen, description: 'The reference is the bag holding the part (A-3). New parts take the first free bag; an emptied bag is reused.' },
] as const satisfies ReadonlyArray<{ value: IpnMode; label: string; icon: typeof Hash; description: string }>

const CHARSET_OPTIONS = [
  { value: 'numeric', label: '0-9' },
  { value: 'alphanumeric', label: 'A-Z + 0-9' },
] as const

interface IpnConfig {
  mode: IpnMode
  prefix: string
  useCategoryCode: boolean
  separator: string
  digits: number
  charset: string
}

// The category code is intrinsic to the category+sequence mode, so it's always
// included there regardless of the toggle.
function includesCategory(cfg: IpnConfig) {
  return cfg.mode === 'category_sequence' || cfg.useCategoryCode
}

// Deterministic pseudo-random body so the preview stays stable across renders
// (a seed derived from the sequence index makes each example differ).
function randomBody(seed: number, digits: number, charset: string) {
  const alphabet = charset === 'alphanumeric' ? 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' : '0123456789'
  let s = (seed >>> 0) || 1
  let out = ''
  for (let i = 0; i < digits; i++) {
    s = (s * 1103515245 + 12345) & 0x7fffffff
    out += alphabet[s % alphabet.length]
  }
  return out
}

function buildIpn(cfg: IpnConfig, sequence: number, categoryCode = 'RES') {
  const body = cfg.mode === 'random'
    ? randomBody(Math.imul(sequence, 2654435761), cfg.digits, cfg.charset)
    : String(sequence).padStart(cfg.digits, '0')
  const segments = [ cfg.prefix, includesCategory(cfg) ? categoryCode : '', body ]
  return segments.filter(Boolean).join(cfg.separator)
}

function buildIpnPattern(cfg: IpnConfig) {
  if (cfg.mode === 'box_bag') return ['BOX', 'N'].join(cfg.separator)
  const bodyChar = cfg.mode === 'random' && cfg.charset === 'alphanumeric' ? 'X' : 'N'
  const segments = [ cfg.prefix, includesCategory(cfg) ? 'CAT' : '', bodyChar.repeat(cfg.digits) ]
  return segments.filter(Boolean).join(cfg.separator)
}

// Mirrors the design-makerstorage prototype's separator order (-, ., None, /),
// with the model's extra "_" option appended since it has no prototype counterpart.
function orderSeparators(separators: string[]) {
  const withoutSlash = separators.filter((s) => s !== '/')
  return [...withoutSlash, '', ...(separators.includes('/') ? ['/'] : [])]
}

interface IpnSectionProps {
  form: IpnForm
  organization: OrganizationSettings
  separators: string[]
}

// IPN (internal part number) format: live preview, generation mode,
// composition, and renumbering existing parts.
export function IpnSection({ form, organization, separators }: IpnSectionProps) {
  const saveIpn = () => form.patch('/settings', { preserveScroll: true })

  const [reassigning, setReassigning] = useState(false)
  const reassignIpns = () => {
    router.post('/settings/reassign_ipns', {}, {
      preserveScroll: true,
      onStart: () => setReassigning(true),
      onFinish: () => setReassigning(false),
    })
  }

  const submitIpn = (e: FormEvent) => {
    e.preventDefault()
    // Changing the format doesn't renumber existing parts — only new ones use
    // it — so confirm before saving to make that non-obvious behavior explicit.
    if (formatChanged) {
      setIpnConfirmOpen(true)
    } else {
      saveIpn()
    }
  }

  const ipnMode = form.data.organization.ipn_generation_mode

  const [ipnConfirmOpen, setIpnConfirmOpen] = useState(false)

  // Whether any format-affecting IPN setting differs from what's saved. Only
  // these change how future references look; `ipn_next_sequence` alone doesn't
  // warrant the confirmation.
  const ipnData = form.data.organization
  const formatChanged =
    ipnData.ipn_generation_mode !== organization.ipn_generation_mode ||
    ipnData.ipn_charset !== organization.ipn_charset ||
    ipnData.ipn_prefix !== organization.ipn_prefix ||
    ipnData.ipn_separator !== organization.ipn_separator ||
    ipnData.ipn_digits !== organization.ipn_digits ||
    ipnData.ipn_use_category_code !== organization.ipn_use_category_code

  const livePreview = useMemo(() => {
    const o = form.data.organization
    const cfg: IpnConfig = {
      mode: o.ipn_generation_mode,
      prefix: o.ipn_prefix,
      useCategoryCode: o.ipn_use_category_code,
      separator: o.ipn_separator,
      digits: Number(o.ipn_digits) || 1,
      charset: o.ipn_charset,
    }
    // Box & bag: the next free bags (codes follow the saved separator), or
    // sample codes when no bag is free yet.
    if (cfg.mode === 'box_bag') {
      const codes = cfg.separator === organization.ipn_separator && organization.free_bag_codes.length > 0
        ? organization.free_bag_codes
        : ['A', 'A', 'A', 'B'].map((box, i) => [box, box === 'A' ? i + 1 : 1].join(cfg.separator))
      return { next: codes[0], examples: codes.slice(1), pattern: buildIpnPattern(cfg) }
    }
    // A category+sequence counter is conceptually per-category, so it starts at 1.
    const start = cfg.mode === 'category_sequence' ? 1 : Number(o.ipn_next_sequence) || 1
    return {
      next: buildIpn(cfg, start),
      examples: [1, 2, 3].map((i) => buildIpn(cfg, start + i)),
      pattern: buildIpnPattern(cfg),
    }
  }, [form.data.organization, organization.ipn_separator, organization.free_bag_codes])

  return (
    <form onSubmit={submitIpn} className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Reference numbering (IPN)</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          The IPN (Internal Part Number) is the unique identifier assigned to every new component.
        </p>
      </div>

      {/* Live preview */}
      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-5 text-zinc-50">
        <div className="mb-3 text-xs font-semibold tracking-wide text-zinc-400 uppercase">Live preview</div>
        <div className="flex flex-wrap items-end gap-5">
          <div>
            <div className="mb-1 text-xs text-zinc-400">
              {ipnMode === 'box_bag' ? 'Next free bag' : 'Next reference generated'}
            </div>
            <div className="font-mono text-3xl font-semibold text-primary">{livePreview.next}</div>
          </div>
          <div className="min-w-[180px] flex-1">
            <div className="mb-1.5 text-xs text-zinc-400">Then follows</div>
            <div className="flex flex-wrap gap-1.5">
              {livePreview.examples.map((example) => (
                <span key={example} className="rounded-md border border-zinc-800 bg-zinc-900 px-2.5 py-1 font-mono text-sm text-zinc-200">
                  {example}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Generation mode */}
      <Card>
        <CardHeader>
          <CardTitle>Generation mode</CardTitle>
          <CardDescription>How the numeric part of each reference is assigned.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-2.5 sm:grid-cols-2">
          {IPN_MODES.map((m) => {
            const active = ipnMode === m.value
            return (
              <Button
                key={m.value}
                type="button"
                variant="ghost"
                onClick={() => form.setData('organization', { ...form.data.organization, ipn_generation_mode: m.value })}
                className={`h-auto flex-col items-stretch justify-start gap-0 rounded-lg border-[1.5px] p-3 text-left font-normal whitespace-normal ${
                  active ? 'border-primary bg-accent dark:hover:bg-accent' : 'border-border'
                }`}
              >
                <div className="flex items-center gap-2">
                  <m.icon className={`size-4 shrink-0 ${active ? 'text-primary' : 'text-muted-foreground'}`} />
                  <span className="text-sm font-semibold">{m.label}</span>
                  {active && <Check className="ml-auto size-4 text-primary" />}
                </div>
                <p className="mt-1.5 text-xs leading-relaxed text-muted-foreground">{m.description}</p>
              </Button>
            )
          })}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Composition</CardTitle>
          <CardDescription>The segments that make up each reference.</CardDescription>
        </CardHeader>
        <CardContent className="divide-y">
          {ipnMode === 'box_bag' && (
            <div className="flex items-start gap-2 py-3 text-xs text-muted-foreground first:pt-0">
              <PackageOpen className="mt-0.5 size-3.5 shrink-0" />
              <span>
                Each box is a storage zone of type Box with a code (A, B, C…); add numbered bags to it from
                Storage zones. A bag is free when no part holds it, or once its part has been emptied out of it.{' '}
                {organization.free_bags_count === 0
                  ? 'No bag is free right now.'
                  : `${organization.free_bags_count} ${organization.free_bags_count === 1 ? 'bag is' : 'bags are'} free.`}
              </span>
            </div>
          )}
          {ipnMode !== 'box_bag' && (<>
          <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
            <div>
              <div className="text-sm font-medium">Prefix</div>
              <div className="text-xs text-muted-foreground">Text placed at the start of every reference.</div>
            </div>
            <Input
              className="w-28 text-center font-mono"
              maxLength={6}
              value={form.data.organization.ipn_prefix}
              onChange={(e) => form.setData('organization', {
                ...form.data.organization,
                ipn_prefix: e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6),
              })}
            />
          </div>
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">Include category code</div>
              <div className="text-xs text-muted-foreground">
                {ipnMode === 'category_sequence'
                  ? 'Always included in the category + sequence mode.'
                  : 'Inserts a code (RES, CAP, IC…) between the prefix and the number.'}
              </div>
            </div>
            <Switch
              disabled={ipnMode === 'category_sequence'}
              checked={ipnMode === 'category_sequence' || form.data.organization.ipn_use_category_code}
              onCheckedChange={(checked) => form.setData('organization', { ...form.data.organization, ipn_use_category_code: checked })}
            />
          </div>
          </>)}
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">Separator</div>
              <div className="text-xs text-muted-foreground">
                {ipnMode === 'box_bag' ? 'Character between the box and the bag number.' : 'Character between segments.'}
              </div>
            </div>
            <div className="flex gap-1.5">
              {orderSeparators(separators).map((sep) => {
                const active = form.data.organization.ipn_separator === sep
                return (
                  <Button
                    key={sep || 'none'}
                    type="button"
                    variant={active ? 'default' : 'outline'}
                    size="sm"
                    onClick={() => form.setData('organization', { ...form.data.organization, ipn_separator: sep })}
                    className={`min-w-9 border px-2.5 font-mono font-semibold shadow-none ${
                      active ? 'border-transparent' : 'text-muted-foreground'
                    }`}
                  >
                    {SEPARATOR_LABELS[sep] ?? sep}
                  </Button>
                )
              })}
            </div>
          </div>
          {ipnMode !== 'box_bag' && (
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">Number length</div>
              <div className="text-xs text-muted-foreground">
                {ipnMode === 'random' ? 'How many characters the random body uses.' : 'The sequence is left-padded with zeros to this length.'}
              </div>
            </div>
            <Select
              value={String(form.data.organization.ipn_digits)}
              onValueChange={(value) => form.setData('organization', { ...form.data.organization, ipn_digits: Number(value) })}
            >
              <SelectTrigger className="w-24"><SelectValue /></SelectTrigger>
              <SelectContent>
                {DIGIT_OPTIONS.map((n) => (
                  <SelectItem key={n} value={String(n)}>{n} digits</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          )}
          {(ipnMode === 'incremental' || ipnMode === 'category_sequence') && (
            <div className="flex items-center justify-between gap-4 py-3 last:pb-0">
              <div>
                <div className="text-sm font-medium">Next sequence number</div>
                <div className="text-xs text-muted-foreground">
                  {ipnMode === 'category_sequence'
                    ? 'Each category keeps its own counter, incrementing by +1 per component.'
                    : 'The counter increments by +1 for every new component.'}
                </div>
              </div>
              <Input
                className="w-28 text-center font-mono"
                inputMode="numeric"
                value={form.data.organization.ipn_next_sequence}
                onChange={(e) => form.setData('organization', {
                  ...form.data.organization,
                  ipn_next_sequence: Number(e.target.value.replace(/[^0-9]/g, '').slice(0, 7)) || 0,
                })}
              />
            </div>
          )}
          {ipnMode === 'random' && (
            <>
              <div className="flex items-center justify-between gap-4 py-3">
                <div>
                  <div className="text-sm font-medium">Character set</div>
                  <div className="text-xs text-muted-foreground">Digits only, or alphanumeric for more combinations.</div>
                </div>
                <div className="flex gap-1.5">
                  {CHARSET_OPTIONS.map((c) => {
                    const active = form.data.organization.ipn_charset === c.value
                    return (
                      <Button
                        key={c.value}
                        type="button"
                        variant={active ? 'default' : 'outline'}
                        size="sm"
                        onClick={() => form.setData('organization', { ...form.data.organization, ipn_charset: c.value })}
                        className={`border px-3 text-xs shadow-none ${
                          active ? 'border-transparent' : 'text-muted-foreground'
                        }`}
                      >
                        {c.label}
                      </Button>
                    )
                  })}
                </div>
              </div>
              <div className="flex items-center gap-2 py-3 text-xs text-amber-700 dark:text-amber-400 last:pb-0">
                <TriangleAlert className="size-3.5 shrink-0" />
                Uniqueness is checked at creation — a collision triggers a fresh draw automatically.
              </div>
            </>
          )}
          {ipnMode === 'manual' && (
            <div className="flex items-center gap-2 py-3 text-xs text-muted-foreground last:pb-0">
              <Pencil className="size-3.5 shrink-0" />
              In manual mode the operator types the reference freely; the settings above only provide a suggested pre-filled value.
            </div>
          )}
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          <Button type="button" variant="outline" onClick={() => form.reset()}>Reset</Button>
          <Button type="submit" disabled={form.processing}>Save</Button>
        </CardFooter>
      </Card>

      {/* Renumber existing parts to the saved format. Hidden in manual
          mode (nothing to generate) and disabled while the format has
          unsaved edits, since the server uses the saved settings. */}
      {ipnMode !== 'manual' && (
        <Card>
          <CardHeader>
            <CardTitle>Reassign existing references</CardTitle>
            <CardDescription>
              {organization.ipn_generation_mode === 'box_bag'
                ? <>Give every part the code of its bag. A part without a bag takes the bag its stock sits in, if
                  no other part holds it; the others lose their reference.</>
                : <>Renumber every part with the current saved format. A format change only affects new
                  parts — use this to bring the {organization.parts_count} existing{' '}
                  {organization.parts_count === 1 ? 'part' : 'parts'} in line with it.</>}
            </CardDescription>
          </CardHeader>
          <CardFooter className="flex-wrap justify-between gap-2 border-t">
            <p className="text-xs text-muted-foreground">
              {formatChanged
                ? 'Save your format changes first to renumber with them.'
                : 'Overwrites the reference on every part — this can’t be undone.'}
            </p>
            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button
                  type="button"
                  variant="outline"
                  disabled={formatChanged || reassigning || organization.parts_count === 0}
                >
                  {reassigning ? 'Reassigning…' : 'Reassign IPNs'}
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>Reassign every part’s IPN?</AlertDialogTitle>
                  <AlertDialogDescription>
                    All {organization.parts_count} existing{' '}
                    {organization.parts_count === 1 ? 'part' : 'parts'} will be renumbered in creation
                    order using your saved format, replacing their current references. This can’t be undone.
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>Cancel</AlertDialogCancel>
                  <AlertDialogAction onClick={reassignIpns}>Reassign IPNs</AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>
          </CardFooter>
        </Card>
      )}

      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <Info className="size-3.5 shrink-0" />
        Current format:{' '}
        <code className="rounded-md border bg-card px-1.5 py-0.5 font-mono text-foreground">
          {livePreview.pattern}
        </code>
      </div>

      {/* Confirm before changing the format: existing parts keep their
          numbers, so make clear only new parts are affected. */}
      <AlertDialog open={ipnConfirmOpen} onOpenChange={setIpnConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Change the numbering format?</AlertDialogTitle>
            <AlertDialogDescription>
              New components will be numbered <span className="font-mono">{livePreview.next}</span> and onward.
              Existing parts keep the reference numbers they already have — they are not renumbered, so your
              inventory will hold a mix of the old and new formats.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={saveIpn}>Save changes</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </form>
  )
}
