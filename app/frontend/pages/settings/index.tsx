import { Head, useForm } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import { Building2, Hash, Package, Info } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

interface IpnPreview {
  next: string
  examples: string[]
}

interface OrganizationSettings {
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
  ipn_prefix: string
  ipn_separator: string
  ipn_digits: number
  ipn_use_category_code: boolean
  ipn_next_sequence: number
  default_low_stock_threshold: number
  allow_negative_stock: boolean
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
] as const

type SectionKey = (typeof SECTIONS)[number]['key']

function buildIpn(prefix: string, useCategoryCode: boolean, separator: string, digits: number, sequence: number, categoryCode = 'RES') {
  const segments = [ prefix || '' ]
  if (useCategoryCode) segments.push(categoryCode)
  segments.push(String(sequence).padStart(digits, '0'))
  return segments.join(separator)
}

function buildIpnPattern(prefix: string, useCategoryCode: boolean, separator: string, digits: number) {
  const segments = [ prefix || '' ]
  if (useCategoryCode) segments.push('CAT')
  segments.push('N'.repeat(digits))
  return segments.join(separator)
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

export default function SettingsIndex({ organization, currencies, ipn_separators, timezones }: SettingsPageProps) {
  const [section, setSection] = useState<SectionKey>('general')

  const generalForm = useForm<GeneralFormData>({
    organization: {
      name: organization.name,
      email: organization.email || '',
      phone: organization.phone || '',
      website: organization.website || '',
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

  const submitGeneral = (e: FormEvent) => {
    e.preventDefault()
    generalForm.patch('/settings', { preserveScroll: true })
  }

  const submitIpn = (e: FormEvent) => {
    e.preventDefault()
    ipnForm.patch('/settings', { preserveScroll: true })
  }

  const submitInventory = (e: FormEvent) => {
    e.preventDefault()
    inventoryForm.patch('/settings', { preserveScroll: true })
  }

  const livePreview = useMemo(() => {
    const { ipn_prefix, ipn_use_category_code, ipn_separator, ipn_digits, ipn_next_sequence } = ipnForm.data.organization
    const digits = Number(ipn_digits) || 1
    const seq = Number(ipn_next_sequence) || 1
    return {
      next: buildIpn(ipn_prefix, ipn_use_category_code, ipn_separator, digits, seq),
      examples: [1, 2, 3].map((i) => buildIpn(ipn_prefix, ipn_use_category_code, ipn_separator, digits, seq + i)),
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
            {SECTIONS.map((s) => (
              <button
                key={s.key}
                type="button"
                onClick={() => setSection(s.key)}
                className={`flex items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm font-medium whitespace-nowrap transition-colors ${
                  section === s.key ? 'bg-muted text-foreground' : 'text-muted-foreground hover:bg-accent'
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
                      <Select
                        value={generalForm.data.organization.timezone}
                        onValueChange={(value) => generalForm.setData('organization', { ...generalForm.data.organization, timezone: value })}
                      >
                        <SelectTrigger className="w-56"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {timezones.map((tz) => (
                            <SelectItem key={tz} value={tz}>{tz}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
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

                <Card>
                  <CardHeader>
                    <CardTitle>Composition</CardTitle>
                    <CardDescription>References are generated sequentially from an incrementing counter.</CardDescription>
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
                        <div className="text-xs text-muted-foreground">Inserts a code (RES, CAP, IC…) between the prefix and the number.</div>
                      </div>
                      <Switch
                        checked={ipnForm.data.organization.ipn_use_category_code}
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
                        <div className="text-xs text-muted-foreground">The sequence is left-padded with zeros.</div>
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
                    <div className="flex items-center justify-between gap-4 py-3 last:pb-0">
                      <div>
                        <div className="text-sm font-medium">Next sequence number</div>
                        <div className="text-xs text-muted-foreground">The counter increments by +1 for every new component.</div>
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
                    {buildIpnPattern(
                      ipnForm.data.organization.ipn_prefix,
                      ipnForm.data.organization.ipn_use_category_code,
                      ipnForm.data.organization.ipn_separator,
                      Number(ipnForm.data.organization.ipn_digits) || 1
                    )}
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
          </div>
        </div>
      </div>
    </AppLayout>
  )
}
