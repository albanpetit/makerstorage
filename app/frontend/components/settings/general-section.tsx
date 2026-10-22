import { ChangeEvent, FormEvent, useEffect, useMemo, useRef } from 'react'
import { Upload, Trash2 } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
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

import type { GeneralForm, OrganizationSettings } from './types'
import { t } from '@/lib/i18n'

const CURRENCY_LABELS: Record<string, string> = {
  EUR: 'EUR (€)',
  USD: 'USD ($)',
  GBP: 'GBP (£)',
  CHF: 'CHF',
}

interface GeneralSectionProps {
  form: GeneralForm
  organization: OrganizationSettings
  currencies: string[]
  timezones: string[]
}

// Organization profile, logo, address and regional preferences.
export function GeneralSection({ form, organization, currencies, timezones }: GeneralSectionProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)

  const pendingLogo = form.data.organization.logo
  const removeLogo = form.data.organization.remove_logo

  // Preview the freshly-picked file locally; otherwise show the stored logo
  // unless the user has staged a removal.
  const localPreview = useMemo(() => (pendingLogo ? URL.createObjectURL(pendingLogo) : null), [pendingLogo])
  useEffect(() => () => { if (localPreview) URL.revokeObjectURL(localPreview) }, [localPreview])
  const logoSrc = localPreview ?? (removeLogo ? null : organization.logo_url)

  const handleLogoChange = (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0] ?? null
    form.setData('organization', { ...form.data.organization, logo: file, remove_logo: false })
  }

  const handleRemoveLogo = () => {
    if (fileInputRef.current) fileInputRef.current.value = ''
    form.setData('organization', { ...form.data.organization, logo: null, remove_logo: true })
  }

  const submitGeneral = (e: FormEvent) => {
    e.preventDefault()
    // Only send the `logo` key when a new file is staged — sending a null logo
    // would otherwise be treated as "clear the attachment" by the server.
    form.transform((data) => {
      const org = { ...data.organization }
      if (!org.logo) delete (org as { logo?: File | null }).logo
      return { organization: org }
    })
    form.patch('/settings', {
      preserveScroll: true,
      onSuccess: () => form.setData('organization', { ...form.data.organization, logo: null, remove_logo: false }),
    })
  }

  return (
    <form onSubmit={submitGeneral} className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">{t('General')}</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          {t('Organization profile and global workspace preferences.')}
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{t('Organization profile')}</CardTitle>
          <CardDescription>{t('Shown on purchase orders and shared with your team.')}</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <div className="flex items-center gap-4 sm:col-span-2">
            <Avatar className="size-16 rounded-lg">
              {logoSrc && <AvatarImage src={logoSrc} alt={t('Organization logo')} className="object-cover" />}
              <AvatarFallback className="rounded-lg text-lg font-semibold">
                {organization.name.trim().charAt(0).toUpperCase() || '?'}
              </AvatarFallback>
            </Avatar>
            <div className="space-y-1.5">
              <div className="flex flex-wrap gap-2">
                <Button type="button" variant="outline" size="sm" onClick={() => fileInputRef.current?.click()}>
                  <Upload className="size-4" /> {logoSrc ? t('Replace logo') : t('Upload logo')}
                </Button>
                {logoSrc && (
                  <Button type="button" variant="ghost" size="sm" onClick={handleRemoveLogo}>
                    <Trash2 className="size-4" /> {t('Remove')}
                  </Button>
                )}
              </div>
              <p className="text-xs text-muted-foreground">{t('PNG, JPG or SVG. Shown in the sidebar and on documents.')}</p>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/png,image/jpeg,image/svg+xml,image/webp"
                className="hidden"
                onChange={handleLogoChange}
              />
            </div>
          </div>
          {form.errors['organization.logo'] && (
            <FieldError className="sm:col-span-2">{form.errors['organization.logo']}</FieldError>
          )}
          <Field className="sm:col-span-2">
            <FieldLabel><Label>{t('Name')}</Label></FieldLabel>
            <FieldContent>
              <Input
                value={form.data.organization.name}
                onChange={(e) => form.setData('organization', { ...form.data.organization, name: e.target.value })}
              />
            </FieldContent>
            {form.errors['organization.name'] && <FieldError>{form.errors['organization.name']}</FieldError>}
          </Field>
          <Field>
            <FieldLabel><Label>{t('Email')}</Label></FieldLabel>
            <FieldContent>
              <Input
                type="email"
                value={form.data.organization.email}
                onChange={(e) => form.setData('organization', { ...form.data.organization, email: e.target.value })}
              />
            </FieldContent>
            {form.errors['organization.email'] && <FieldError>{form.errors['organization.email']}</FieldError>}
          </Field>
          <Field>
            <FieldLabel><Label>{t('Phone')}</Label></FieldLabel>
            <FieldContent>
              <Input
                value={form.data.organization.phone}
                onChange={(e) => form.setData('organization', { ...form.data.organization, phone: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field className="sm:col-span-2">
            <FieldLabel><Label>{t('Website')}</Label></FieldLabel>
            <FieldContent>
              <Input
                placeholder={t('https://')}
                value={form.data.organization.website}
                onChange={(e) => form.setData('organization', { ...form.data.organization, website: e.target.value })}
              />
            </FieldContent>
            {form.errors['organization.website'] && <FieldError>{form.errors['organization.website']}</FieldError>}
          </Field>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('Address')}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <Field className="sm:col-span-2">
            <FieldLabel><Label>{t('Address line 1')}</Label></FieldLabel>
            <FieldContent>
              <Input
                value={form.data.organization.address_line1}
                onChange={(e) => form.setData('organization', { ...form.data.organization, address_line1: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field className="sm:col-span-2">
            <FieldLabel><Label>{t('Address line 2')}</Label></FieldLabel>
            <FieldContent>
              <Input
                value={form.data.organization.address_line2}
                onChange={(e) => form.setData('organization', { ...form.data.organization, address_line2: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field>
            <FieldLabel><Label>{t('City')}</Label></FieldLabel>
            <FieldContent>
              <Input
                value={form.data.organization.city}
                onChange={(e) => form.setData('organization', { ...form.data.organization, city: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field>
            <FieldLabel><Label>{t('Postcode')}</Label></FieldLabel>
            <FieldContent>
              <Input
                value={form.data.organization.postcode}
                onChange={(e) => form.setData('organization', { ...form.data.organization, postcode: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field className="sm:col-span-2">
            <FieldLabel><Label>{t('Country')}</Label></FieldLabel>
            <FieldContent>
              <Input
                value={form.data.organization.country}
                onChange={(e) => form.setData('organization', { ...form.data.organization, country: e.target.value })}
              />
            </FieldContent>
          </Field>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('Regional preferences')}</CardTitle>
        </CardHeader>
        <CardContent className="divide-y">
          <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
            <div>
              <div className="text-sm font-medium">{t('Currency')}</div>
              <div className="text-xs text-muted-foreground">{t('Displayed prices and stock valuation.')}</div>
            </div>
            <Select
              value={form.data.organization.currency}
              onValueChange={(value) => form.setData('organization', { ...form.data.organization, currency: value })}
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
              <div className="text-sm font-medium">{t('Timezone')}</div>
              <div className="text-xs text-muted-foreground">{t('Timestamps on stock movements.')}</div>
            </div>
            <Combobox
              className="w-56"
              value={form.data.organization.timezone}
              onValueChange={(value) => form.setData('organization', { ...form.data.organization, timezone: value })}
              options={timezones.map((tz) => ({ value: tz, label: tz }))}
              placeholder={t('Select timezone')}
              searchPlaceholder={t('Search timezones…')}
              emptyText={t('No timezone found.')}
            />
          </div>
        </CardContent>
        <CardFooter className="justify-end border-t">
          <Button type="submit" disabled={form.processing}>{t('Save')}</Button>
        </CardFooter>
      </Card>
    </form>
  )
}
