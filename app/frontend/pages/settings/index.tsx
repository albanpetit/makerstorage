import { Head, router, useForm } from '@inertiajs/react'
import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import { Building2, Hash, Package, Info, TrendingUp, Shuffle, Boxes, Pencil, Check, TriangleAlert, ShieldAlert, Upload, Trash2, Plug, CircleCheck } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { usePermissions } from '@/hooks/use-permissions'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Combobox } from '@/components/ui/combobox'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
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

interface IpnPreview {
  next: string
  examples: string[]
}

interface OrganizationSettings {
  id: number
  logo_url: string | null
  name: string
  email: string | null
  phone: string | null
  website: string | null
  address_line1: string | null
  address_line2: string | null
  city: string | null
  postcode: string | null
  country: string | null
  currency: string
  timezone: string
  ipn_generation_mode: IpnMode
  ipn_charset: string
  ipn_prefix: string
  ipn_separator: string
  ipn_digits: number
  ipn_use_category_code: boolean
  ipn_next_sequence: number
  default_low_stock_threshold: number
  allow_negative_stock: boolean
  mouser_api_key_present: boolean
  ipn_preview: IpnPreview
}

interface SettingsPageProps {
  organization: OrganizationSettings
  currencies: string[]
  ipn_separators: string[]
  timezones: string[]
}

const CURRENCY_LABELS: Record<string, string> = {
  EUR: 'EUR (€)',
  USD: 'USD ($)',
  GBP: 'GBP (£)',
  CHF: 'CHF',
}

const SEPARATOR_LABELS: Record<string, string> = {
  '-': '-',
  '.': '.',
  _: '_',
  '/': '/',
  '': 'None',
}

const DIGIT_OPTIONS = [3, 4, 5, 6, 7, 8]

const SECTIONS = [
  { key: 'general', label: 'General', icon: Building2 },
  { key: 'ipn', label: 'Numbering (IPN)', icon: Hash },
  { key: 'inventory', label: 'Inventory', icon: Package },
  { key: 'integrations', label: 'Integrations', icon: Plug },
  { key: 'danger', label: 'Danger zone', icon: ShieldAlert },
] as const

type SectionKey = (typeof SECTIONS)[number]['key']

type IpnMode = 'incremental' | 'random' | 'category_sequence' | 'manual'

const IPN_MODES = [
  { value: 'incremental', label: 'Incremental', icon: TrendingUp, description: 'Auto-incrementing sequential counter. Ordered, predictable references.' },
  { value: 'random', label: 'Random', icon: Shuffle, description: 'Unique non-sequential draw. Avoids revealing how many parts exist.' },
  { value: 'category_sequence', label: 'Category + sequence', icon: Boxes, description: 'An independent counter per category (RES-00001, CAP-00001…).' },
  { value: 'manual', label: 'Manual', icon: Pencil, description: 'Free entry by the operator, with a suggested value.' },
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

interface GeneralFormData {
  organization: {
    name: string
    email: string
    phone: string
    website: string
    logo: File | null
    remove_logo: boolean
    address_line1: string
    address_line2: string
    city: string
    postcode: string
    country: string
    currency: string
    timezone: string
  }
}

interface IpnFormData {
  organization: {
    ipn_generation_mode: IpnMode
    ipn_charset: string
    ipn_prefix: string
    ipn_separator: string
    ipn_digits: number
    ipn_use_category_code: boolean
    ipn_next_sequence: number
  }
}

interface InventoryFormData {
  organization: {
    default_low_stock_threshold: number
    allow_negative_stock: boolean
  }
}

interface IntegrationsFormData {
  organization: {
    mouser_api_key: string
    remove_mouser_api_key: boolean
  }
}

export default function SettingsIndex({ organization, currencies, ipn_separators, timezones }: SettingsPageProps) {
  const { isOwner } = usePermissions()
  const [section, setSection] = useState<SectionKey>('general')

  const sections = useMemo(() => SECTIONS.filter((s) => s.key !== 'danger' || isOwner), [isOwner])

  const generalForm = useForm<GeneralFormData>({
    organization: {
      name: organization.name,
      email: organization.email || '',
      phone: organization.phone || '',
      website: organization.website || '',
      logo: null,
      remove_logo: false,
      address_line1: organization.address_line1 || '',
      address_line2: organization.address_line2 || '',
      city: organization.city || '',
      postcode: organization.postcode || '',
      country: organization.country || '',
      currency: organization.currency,
      timezone: organization.timezone,
    },
  })

  const ipnForm = useForm<IpnFormData>({
    organization: {
      ipn_generation_mode: organization.ipn_generation_mode,
      ipn_charset: organization.ipn_charset,
      ipn_prefix: organization.ipn_prefix,
      ipn_separator: organization.ipn_separator,
      ipn_digits: organization.ipn_digits,
      ipn_use_category_code: organization.ipn_use_category_code,
      ipn_next_sequence: organization.ipn_next_sequence,
    },
  })

  const inventoryForm = useForm<InventoryFormData>({
    organization: {
      default_low_stock_threshold: organization.default_low_stock_threshold,
      allow_negative_stock: organization.allow_negative_stock,
    },
  })

  const integrationsForm = useForm<IntegrationsFormData>({
    organization: {
      mouser_api_key: '',
      remove_mouser_api_key: false,
    },
  })

  const fileInputRef = useRef<HTMLInputElement>(null)
  const [deleteConfirm, setDeleteConfirm] = useState('')

  const pendingLogo = generalForm.data.organization.logo
  const removeLogo = generalForm.data.organization.remove_logo

  // Preview the freshly-picked file locally; otherwise show the stored logo
  // unless the user has staged a removal.
  const localPreview = useMemo(() => (pendingLogo ? URL.createObjectURL(pendingLogo) : null), [pendingLogo])
  useEffect(() => () => { if (localPreview) URL.revokeObjectURL(localPreview) }, [localPreview])
  const logoSrc = localPreview ?? (removeLogo ? null : organization.logo_url)

  const handleLogoChange = (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0] ?? null
    generalForm.setData('organization', { ...generalForm.data.organization, logo: file, remove_logo: false })
  }

  const handleRemoveLogo = () => {
    if (fileInputRef.current) fileInputRef.current.value = ''
    generalForm.setData('organization', { ...generalForm.data.organization, logo: null, remove_logo: true })
  }

  const submitGeneral = (e: FormEvent) => {
    e.preventDefault()
    // Only send the `logo` key when a new file is staged — sending a null logo
    // would otherwise be treated as "clear the attachment" by the server.
    generalForm.transform((data) => {
      const org = { ...data.organization }
      if (!org.logo) delete (org as { logo?: File | null }).logo
      return { organization: org }
    })
    generalForm.patch('/settings', {
      preserveScroll: true,
      onSuccess: () => generalForm.setData('organization', { ...generalForm.data.organization, logo: null, remove_logo: false }),
    })
  }

  const submitIpn = (e: FormEvent) => {
    e.preventDefault()
    ipnForm.patch('/settings', { preserveScroll: true })
  }

  const submitInventory = (e: FormEvent) => {
    e.preventDefault()
    inventoryForm.patch('/settings', { preserveScroll: true })
  }

  const submitIntegrations = (e: FormEvent) => {
    e.preventDefault()
    integrationsForm.patch('/settings', {
      preserveScroll: true,
      onSuccess: () => integrationsForm.setData('organization', { mouser_api_key: '', remove_mouser_api_key: false }),
    })
  }

  const removeMouserKey = () => {
    integrationsForm.transform((data) => ({
      organization: { ...data.organization, mouser_api_key: '', remove_mouser_api_key: true },
    }))
    integrationsForm.patch('/settings', {
      preserveScroll: true,
      onSuccess: () => {
        integrationsForm.setData('organization', { mouser_api_key: '', remove_mouser_api_key: false })
        integrationsForm.transform((data) => data)
      },
    })
  }

  const ipnMode = ipnForm.data.organization.ipn_generation_mode

  const livePreview = useMemo(() => {
    const o = ipnForm.data.organization
    const cfg: IpnConfig = {
      mode: o.ipn_generation_mode,
      prefix: o.ipn_prefix,
      useCategoryCode: o.ipn_use_category_code,
      separator: o.ipn_separator,
      digits: Number(o.ipn_digits) || 1,
      charset: o.ipn_charset,
    }
    // A category+sequence counter is conceptually per-category, so it starts at 1.
    const start = cfg.mode === 'category_sequence' ? 1 : Number(o.ipn_next_sequence) || 1
    return {
      next: buildIpn(cfg, start),
      examples: [1, 2, 3].map((i) => buildIpn(cfg, start + i)),
      pattern: buildIpnPattern(cfg),
    }
  }, [ipnForm.data.organization])

  return (
    <AppLayout header={<PageHeader title="Settings" subtitle="Organization configuration and preferences" />}>
      <Head title="Settings" />

      <div className="space-y-6">
        <FlashMessages />

        <div className="flex flex-col gap-6 lg:flex-row">
          {/* Section nav */}
          <nav className="flex shrink-0 gap-1 overflow-x-auto lg:w-56 lg:flex-col lg:overflow-visible">
            {sections.map((s) => (
              <button
                key={s.key}
                type="button"
                onClick={() => setSection(s.key)}
                className={`flex items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm font-medium whitespace-nowrap transition-colors ${
                  section === s.key
                    ? 'bg-muted text-foreground'
                    : s.key === 'danger'
                      ? 'text-destructive hover:bg-destructive/10'
                      : 'text-muted-foreground hover:bg-accent'
                }`}
              >
                <s.icon className="size-4 shrink-0" />
                {s.label}
              </button>
            ))}
          </nav>

          {/* Content — centered and capped like the mockup's 780px column */}
          <div className="mx-auto w-full min-w-0 max-w-[780px] space-y-4">
            {section === 'general' && (
              <form onSubmit={submitGeneral} className="space-y-4">
                <div>
                  <h2 className="text-lg font-semibold">General</h2>
                  <p className="max-w-xl text-sm text-muted-foreground">
                    Organization profile and global workspace preferences.
                  </p>
                </div>

                <Card>
                  <CardHeader>
                    <CardTitle>Organization profile</CardTitle>
                    <CardDescription>Shown on purchase orders and shared with your team.</CardDescription>
                  </CardHeader>
                  <CardContent className="grid gap-4 sm:grid-cols-2">
                    <div className="flex items-center gap-4 sm:col-span-2">
                      <Avatar className="size-16 rounded-lg">
                        {logoSrc && <AvatarImage src={logoSrc} alt="Organization logo" className="object-cover" />}
                        <AvatarFallback className="rounded-lg text-lg font-semibold">
                          {organization.name.trim().charAt(0).toUpperCase() || '?'}
                        </AvatarFallback>
                      </Avatar>
                      <div className="space-y-1.5">
                        <div className="flex flex-wrap gap-2">
                          <Button type="button" variant="outline" size="sm" onClick={() => fileInputRef.current?.click()}>
                            <Upload className="size-4" /> {logoSrc ? 'Replace' : 'Upload'} logo
                          </Button>
                          {logoSrc && (
                            <Button type="button" variant="ghost" size="sm" onClick={handleRemoveLogo}>
                              <Trash2 className="size-4" /> Remove
                            </Button>
                          )}
                        </div>
                        <p className="text-xs text-muted-foreground">PNG, JPG or SVG. Shown in the sidebar and on documents.</p>
                        <input
                          ref={fileInputRef}
                          type="file"
                          accept="image/png,image/jpeg,image/svg+xml,image/webp"
                          className="hidden"
                          onChange={handleLogoChange}
                        />
                      </div>
                    </div>
                    {generalForm.errors['organization.logo'] && (
                      <FieldError className="sm:col-span-2">{generalForm.errors['organization.logo']}</FieldError>
                    )}
                    <Field className="sm:col-span-2">
                      <FieldLabel><Label>Name</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          value={generalForm.data.organization.name}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, name: e.target.value })}
                        />
                      </FieldContent>
                      {generalForm.errors['organization.name'] && <FieldError>{generalForm.errors['organization.name']}</FieldError>}
                    </Field>
                    <Field>
                      <FieldLabel><Label>Email</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          type="email"
                          value={generalForm.data.organization.email}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, email: e.target.value })}
                        />
                      </FieldContent>
                      {generalForm.errors['organization.email'] && <FieldError>{generalForm.errors['organization.email']}</FieldError>}
                    </Field>
                    <Field>
                      <FieldLabel><Label>Phone</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          value={generalForm.data.organization.phone}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, phone: e.target.value })}
                        />
                      </FieldContent>
                    </Field>
                    <Field className="sm:col-span-2">
                      <FieldLabel><Label>Website</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          placeholder="https://"
                          value={generalForm.data.organization.website}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, website: e.target.value })}
                        />
                      </FieldContent>
                      {generalForm.errors['organization.website'] && <FieldError>{generalForm.errors['organization.website']}</FieldError>}
                    </Field>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Address</CardTitle>
                  </CardHeader>
                  <CardContent className="grid gap-4 sm:grid-cols-2">
                    <Field className="sm:col-span-2">
                      <FieldLabel><Label>Address line 1</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          value={generalForm.data.organization.address_line1}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, address_line1: e.target.value })}
                        />
                      </FieldContent>
                    </Field>
                    <Field className="sm:col-span-2">
                      <FieldLabel><Label>Address line 2</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          value={generalForm.data.organization.address_line2}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, address_line2: e.target.value })}
                        />
                      </FieldContent>
                    </Field>
                    <Field>
                      <FieldLabel><Label>City</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          value={generalForm.data.organization.city}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, city: e.target.value })}
                        />
                      </FieldContent>
                    </Field>
                    <Field>
                      <FieldLabel><Label>Postcode</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          value={generalForm.data.organization.postcode}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, postcode: e.target.value })}
                        />
                      </FieldContent>
                    </Field>
                    <Field className="sm:col-span-2">
                      <FieldLabel><Label>Country</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          value={generalForm.data.organization.country}
                          onChange={(e) => generalForm.setData('organization', { ...generalForm.data.organization, country: e.target.value })}
                        />
                      </FieldContent>
                    </Field>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Regional preferences</CardTitle>
                  </CardHeader>
                  <CardContent className="divide-y">
                    <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
                      <div>
                        <div className="text-sm font-medium">Currency</div>
                        <div className="text-xs text-muted-foreground">Displayed prices and stock valuation.</div>
                      </div>
                      <Select
                        value={generalForm.data.organization.currency}
                        onValueChange={(value) => generalForm.setData('organization', { ...generalForm.data.organization, currency: value })}
                      >
                        <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {currencies.map((currency) => (
                            <SelectItem key={currency} value={currency}>{CURRENCY_LABELS[currency] || currency}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="flex items-center justify-between gap-4 py-3 last:pb-0">
                      <div>
                        <div className="text-sm font-medium">Timezone</div>
                        <div className="text-xs text-muted-foreground">Timestamps on stock movements.</div>
                      </div>
                      <Combobox
                        className="w-56"
                        value={generalForm.data.organization.timezone}
                        onValueChange={(value) => generalForm.setData('organization', { ...generalForm.data.organization, timezone: value })}
                        options={timezones.map((tz) => ({ value: tz, label: tz }))}
                        placeholder="Select timezone"
                        searchPlaceholder="Search timezones…"
                        emptyText="No timezone found."
                      />
                    </div>
                  </CardContent>
                  <CardFooter className="justify-end border-t">
                    <Button type="submit" disabled={generalForm.processing}>Save</Button>
                  </CardFooter>
                </Card>
              </form>
            )}

            {section === 'ipn' && (
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
                      <div className="mb-1 text-xs text-zinc-400">Next reference generated</div>
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
                        <button
                          key={m.value}
                          type="button"
                          onClick={() => ipnForm.setData('organization', { ...ipnForm.data.organization, ipn_generation_mode: m.value })}
                          className={`flex flex-col rounded-lg border-[1.5px] p-3 text-left transition-colors ${
                            active ? 'border-primary bg-accent' : 'border-border hover:bg-accent'
                          }`}
                        >
                          <div className="flex items-center gap-2">
                            <m.icon className={`size-4 shrink-0 ${active ? 'text-primary' : 'text-muted-foreground'}`} />
                            <span className="text-sm font-semibold">{m.label}</span>
                            {active && <Check className="ml-auto size-4 text-primary" />}
                          </div>
                          <p className="mt-1.5 text-xs leading-relaxed text-muted-foreground">{m.description}</p>
                        </button>
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
                    <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
                      <div>
                        <div className="text-sm font-medium">Prefix</div>
                        <div className="text-xs text-muted-foreground">Text placed at the start of every reference.</div>
                      </div>
                      <Input
                        className="w-28 text-center font-mono"
                        maxLength={6}
                        value={ipnForm.data.organization.ipn_prefix}
                        onChange={(e) => ipnForm.setData('organization', {
                          ...ipnForm.data.organization,
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
                        checked={ipnMode === 'category_sequence' || ipnForm.data.organization.ipn_use_category_code}
                        onCheckedChange={(checked) => ipnForm.setData('organization', { ...ipnForm.data.organization, ipn_use_category_code: checked })}
                      />
                    </div>
                    <div className="flex items-center justify-between gap-4 py-3">
                      <div>
                        <div className="text-sm font-medium">Separator</div>
                        <div className="text-xs text-muted-foreground">Character between segments.</div>
                      </div>
                      <div className="flex gap-1.5">
                        {orderSeparators(ipn_separators).map((sep) => {
                          const active = ipnForm.data.organization.ipn_separator === sep
                          return (
                            <button
                              key={sep || 'none'}
                              type="button"
                              onClick={() => ipnForm.setData('organization', { ...ipnForm.data.organization, ipn_separator: sep })}
                              className={`h-8 min-w-9 rounded-md border px-2.5 font-mono text-sm font-semibold transition-colors ${
                                active ? 'border-transparent bg-primary text-primary-foreground' : 'border-border text-muted-foreground hover:bg-accent'
                              }`}
                            >
                              {SEPARATOR_LABELS[sep] ?? sep}
                            </button>
                          )
                        })}
                      </div>
                    </div>
                    <div className="flex items-center justify-between gap-4 py-3">
                      <div>
                        <div className="text-sm font-medium">Number length</div>
                        <div className="text-xs text-muted-foreground">
                          {ipnMode === 'random' ? 'How many characters the random body uses.' : 'The sequence is left-padded with zeros to this length.'}
                        </div>
                      </div>
                      <Select
                        value={String(ipnForm.data.organization.ipn_digits)}
                        onValueChange={(value) => ipnForm.setData('organization', { ...ipnForm.data.organization, ipn_digits: Number(value) })}
                      >
                        <SelectTrigger className="w-24"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {DIGIT_OPTIONS.map((n) => (
                            <SelectItem key={n} value={String(n)}>{n} digits</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
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
                          value={ipnForm.data.organization.ipn_next_sequence}
                          onChange={(e) => ipnForm.setData('organization', {
                            ...ipnForm.data.organization,
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
                              const active = ipnForm.data.organization.ipn_charset === c.value
                              return (
                                <button
                                  key={c.value}
                                  type="button"
                                  onClick={() => ipnForm.setData('organization', { ...ipnForm.data.organization, ipn_charset: c.value })}
                                  className={`h-8 rounded-md border px-3 text-xs font-medium transition-colors ${
                                    active ? 'border-transparent bg-primary text-primary-foreground' : 'border-border text-muted-foreground hover:bg-accent'
                                  }`}
                                >
                                  {c.label}
                                </button>
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
                    <Button type="button" variant="outline" onClick={() => ipnForm.reset()}>Reset</Button>
                    <Button type="submit" disabled={ipnForm.processing}>Save</Button>
                  </CardFooter>
                </Card>

                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <Info className="size-3.5 shrink-0" />
                  Current format:{' '}
                  <code className="rounded-md border bg-card px-1.5 py-0.5 font-mono text-foreground">
                    {livePreview.pattern}
                  </code>
                </div>
              </form>
            )}

            {section === 'inventory' && (
              <form onSubmit={submitInventory} className="space-y-4">
                <div>
                  <h2 className="text-lg font-semibold">Inventory</h2>
                  <p className="max-w-xl text-sm text-muted-foreground">
                    Default behavior applied across the organization's stock.
                  </p>
                </div>

                <Card>
                  <CardHeader>
                    <CardTitle>Stock defaults</CardTitle>
                  </CardHeader>
                  <CardContent className="divide-y">
                    <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
                      <div>
                        <div className="text-sm font-medium">Default low-stock threshold</div>
                        <div className="text-xs text-muted-foreground">Applied to new components unless overridden.</div>
                      </div>
                      <Input
                        type="number"
                        min={0}
                        className="w-28 text-center font-mono"
                        value={inventoryForm.data.organization.default_low_stock_threshold}
                        onChange={(e) => inventoryForm.setData('organization', {
                          ...inventoryForm.data.organization,
                          default_low_stock_threshold: Number(e.target.value) || 0,
                        })}
                      />
                    </div>
                    <div className="flex items-center justify-between gap-4 py-3 last:pb-0">
                      <div>
                        <div className="text-sm font-medium">Allow negative stock</div>
                        <div className="text-xs text-muted-foreground">Permit stock movements that exceed the available quantity.</div>
                      </div>
                      <Switch
                        checked={inventoryForm.data.organization.allow_negative_stock}
                        onCheckedChange={(checked) => inventoryForm.setData('organization', { ...inventoryForm.data.organization, allow_negative_stock: checked })}
                      />
                    </div>
                  </CardContent>
                  <CardFooter className="justify-end border-t">
                    <Button type="submit" disabled={inventoryForm.processing}>Save</Button>
                  </CardFooter>
                </Card>
                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <Info className="size-3.5 shrink-0" />
                  Per-component thresholds set on individual parts always take priority over this default.
                </div>
              </form>
            )}

            {section === 'integrations' && (
              <form onSubmit={submitIntegrations} className="space-y-4">
                <div>
                  <h2 className="text-lg font-semibold">Integrations</h2>
                  <p className="max-w-xl text-sm text-muted-foreground">
                    Connect external supplier catalogs to look up component data by part number.
                  </p>
                </div>

                <Card>
                  <CardHeader>
                    <CardTitle>Mouser Electronics</CardTitle>
                    <CardDescription>
                      Fetch a component's details, datasheet and image from Mouser when adding a part.
                      Create a free API key from the{' '}
                      <a
                        href="https://www.mouser.com/api-hub/"
                        target="_blank"
                        rel="noopener noreferrer"
                        className="font-medium text-primary underline underline-offset-2"
                      >
                        Mouser API Hub
                      </a>
                      .
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    {organization.mouser_api_key_present && (
                      <div className="flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
                        <CircleCheck className="size-4 shrink-0" />
                        An API key is configured. Enter a new key below to replace it.
                      </div>
                    )}
                    <Field>
                      <FieldLabel><Label>API key</Label></FieldLabel>
                      <FieldContent>
                        <Input
                          type="password"
                          autoComplete="off"
                          placeholder={organization.mouser_api_key_present ? '••••••••••••••••' : 'Paste your Mouser API key'}
                          value={integrationsForm.data.organization.mouser_api_key}
                          onChange={(e) => integrationsForm.setData('organization', {
                            ...integrationsForm.data.organization,
                            mouser_api_key: e.target.value,
                          })}
                        />
                      </FieldContent>
                      {integrationsForm.errors['organization.mouser_api_key'] && (
                        <FieldError>{integrationsForm.errors['organization.mouser_api_key']}</FieldError>
                      )}
                    </Field>
                  </CardContent>
                  <CardFooter className="justify-end gap-2 border-t">
                    {organization.mouser_api_key_present && (
                      <Button type="button" variant="outline" onClick={removeMouserKey} disabled={integrationsForm.processing}>
                        Remove key
                      </Button>
                    )}
                    <Button type="submit" disabled={integrationsForm.processing || !integrationsForm.data.organization.mouser_api_key.trim()}>
                      Save
                    </Button>
                  </CardFooter>
                </Card>
              </form>
            )}

            {section === 'danger' && isOwner && (
              <div className="space-y-4">
                <div>
                  <h2 className="text-lg font-semibold">Danger zone</h2>
                  <p className="max-w-xl text-sm text-muted-foreground">
                    Irreversible actions that affect the entire organization.
                  </p>
                </div>

                <Card className="border-destructive/40">
                  <CardHeader>
                    <CardTitle>Delete organization</CardTitle>
                    <CardDescription>
                      Permanently deletes <span className="font-medium text-foreground">{organization.name}</span> and all of its
                      parts, categories, stock movements, suppliers and members. This cannot be undone.
                    </CardDescription>
                  </CardHeader>
                  <CardFooter className="justify-end border-t border-destructive/40">
                    <AlertDialog onOpenChange={() => setDeleteConfirm('')}>
                      <AlertDialogTrigger asChild>
                        <Button type="button" variant="destructive">
                          <Trash2 className="size-4" /> Delete organization
                        </Button>
                      </AlertDialogTrigger>
                      <AlertDialogContent>
                        <AlertDialogHeader>
                          <AlertDialogTitle>Delete this organization?</AlertDialogTitle>
                          <AlertDialogDescription>
                            This permanently removes all data belonging to{' '}
                            <span className="font-medium text-foreground">{organization.name}</span>. To confirm, type the
                            organization name below.
                          </AlertDialogDescription>
                        </AlertDialogHeader>
                        <Input
                          value={deleteConfirm}
                          onChange={(e) => setDeleteConfirm(e.target.value)}
                          placeholder={organization.name}
                          autoFocus
                        />
                        <AlertDialogFooter>
                          <AlertDialogCancel>Cancel</AlertDialogCancel>
                          <AlertDialogAction
                            disabled={deleteConfirm.trim() !== organization.name.trim()}
                            className="bg-destructive text-white hover:bg-destructive/90"
                            onClick={() => router.delete(`/organizations/${organization.id}`)}
                          >
                            Delete organization
                          </AlertDialogAction>
                        </AlertDialogFooter>
                      </AlertDialogContent>
                    </AlertDialog>
                  </CardFooter>
                </Card>
                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <TriangleAlert className="size-3.5 shrink-0" />
                  You'll be switched to another organization after deletion.
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </AppLayout>
  )
}
