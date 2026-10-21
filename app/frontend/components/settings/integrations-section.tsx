import { FormEvent } from 'react'
import { router } from '@inertiajs/react'
import { Plug, CircleCheck } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'

import type { IntegrationsForm, OrganizationSettings } from './types'

interface IntegrationsSectionProps {
  form: IntegrationsForm
  organization: OrganizationSettings
}

// Mouser and DigiKey credentials (write-only), the DigiKey account link, and
// the LCSC switch (no key: LCSC's catalog is queried without an account).
export function IntegrationsSection({ form, organization }: IntegrationsSectionProps) {
  const origin = typeof window !== 'undefined' ? window.location.origin : ''

  const resetIntegrations = () => form.setData('organization', {
    mouser_api_key: '',
    remove_mouser_api_key: false,
    mouser_order_api_key: '',
    remove_mouser_order_api_key: false,
    digikey_client_id: '',
    digikey_client_secret: '',
    remove_digikey: false,
  })

  const submitIntegrations = (e: FormEvent) => {
    e.preventDefault()
    form.patch('/settings', {
      preserveScroll: true,
      onSuccess: resetIntegrations,
    })
  }

  // Stage a one-off removal flag for a single provider, submit, then clear the
  // form back to its neutral (write-only) state regardless of outcome.
  const removeProvider = (flag: 'remove_mouser_api_key' | 'remove_mouser_order_api_key' | 'remove_digikey') => {
    form.transform((data) => ({
      organization: { ...data.organization, [flag]: true },
    }))
    form.patch('/settings', {
      preserveScroll: true,
      onFinish: () => {
        resetIntegrations()
        form.transform((data) => data)
      },
    })
  }

  // LCSC has nothing to type in, so its switch saves straight away (outside the
  // credentials form, whose fields it would otherwise reset).
  const toggleLcsc = (enabled: boolean) => {
    router.patch('/settings', { organization: { lcsc_enabled: enabled } }, { preserveScroll: true })
  }

  return (
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
                value={form.data.organization.mouser_api_key}
                onChange={(e) => form.setData('organization', {
                  ...form.data.organization,
                  mouser_api_key: e.target.value,
                })}
              />
            </FieldContent>
            {form.errors['organization.mouser_api_key'] && (
              <FieldError>{form.errors['organization.mouser_api_key']}</FieldError>
            )}
          </Field>
          <p className="text-xs text-muted-foreground">
            Saving a key sets up a “Mouser Electronics” supplier (if it doesn’t exist yet) so looked-up prices
            fill in automatically when you add parts.
          </p>

          <div className="border-t pt-4">
            {organization.mouser_order_api_key_present && (
              <div className="mb-3 flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
                <CircleCheck className="size-4 shrink-0" />
                An Order API key is configured. Enter a new key below to replace it.
              </div>
            )}
            <Field>
              <FieldLabel><Label>Order API key</Label></FieldLabel>
              <FieldContent>
                <Input
                  type="password"
                  autoComplete="off"
                  placeholder={organization.mouser_order_api_key_present ? '••••••••••••••••' : 'Paste your Mouser Order API key'}
                  value={form.data.organization.mouser_order_api_key}
                  onChange={(e) => form.setData('organization', {
                    ...form.data.organization,
                    mouser_order_api_key: e.target.value,
                  })}
                />
              </FieldContent>
              {form.errors['organization.mouser_order_api_key'] && (
                <FieldError>{form.errors['organization.mouser_order_api_key']}</FieldError>
              )}
            </Field>
            <p className="mt-2 text-xs text-muted-foreground">
              A separate key (from the same API Hub) enables pushing an order to a Mouser cart and importing a
              placed Mouser order. Optional.
            </p>
            {organization.mouser_order_api_key_present && (
              <Button
                type="button"
                variant="outline"
                size="sm"
                className="mt-3"
                onClick={() => removeProvider('remove_mouser_order_api_key')}
                disabled={form.processing}
              >
                Remove order key
              </Button>
            )}
          </div>
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          {organization.mouser_api_key_present && (
            <Button type="button" variant="outline" onClick={() => removeProvider('remove_mouser_api_key')} disabled={form.processing}>
              Remove key
            </Button>
          )}
          <Button
            type="submit"
            disabled={
              form.processing ||
              (!form.data.organization.mouser_api_key.trim() &&
                !form.data.organization.mouser_order_api_key.trim())
            }
          >
            Save
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>DigiKey Electronics</CardTitle>
          <CardDescription>
            Fetch a component's details, datasheet and image from DigiKey when adding a part.
            Create an app to get a Client ID and Secret from the{' '}
            <a
              href="https://developer.digikey.com/"
              target="_blank"
              rel="noopener noreferrer"
              className="font-medium text-primary underline underline-offset-2"
            >
              DigiKey developer portal
            </a>
            .
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {organization.digikey_configured && (
            <div className="flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
              <CircleCheck className="size-4 shrink-0" />
              Credentials are configured. Enter new values below to replace them.
            </div>
          )}
          <Field>
            <FieldLabel><Label>Client ID</Label></FieldLabel>
            <FieldContent>
              <Input
                type="password"
                autoComplete="off"
                placeholder={organization.digikey_configured ? '••••••••••••••••' : 'Paste your DigiKey Client ID'}
                value={form.data.organization.digikey_client_id}
                onChange={(e) => form.setData('organization', {
                  ...form.data.organization,
                  digikey_client_id: e.target.value,
                })}
              />
            </FieldContent>
            {form.errors['organization.digikey_client_id'] && (
              <FieldError>{form.errors['organization.digikey_client_id']}</FieldError>
            )}
          </Field>
          <Field>
            <FieldLabel><Label>Client Secret</Label></FieldLabel>
            <FieldContent>
              <Input
                type="password"
                autoComplete="off"
                placeholder={organization.digikey_configured ? '••••••••••••••••' : 'Paste your DigiKey Client Secret'}
                value={form.data.organization.digikey_client_secret}
                onChange={(e) => form.setData('organization', {
                  ...form.data.organization,
                  digikey_client_secret: e.target.value,
                })}
              />
            </FieldContent>
            {form.errors['organization.digikey_client_secret'] && (
              <FieldError>{form.errors['organization.digikey_client_secret']}</FieldError>
            )}
          </Field>
          <p className="text-xs text-muted-foreground">
            Saving credentials sets up a “DigiKey” supplier (if it doesn’t exist yet) so looked-up prices fill in
            automatically when you add parts.
          </p>

          <div className="border-t pt-4">
            <Label>Order import</Label>
            <p className="mt-1 mb-3 text-xs text-muted-foreground">
              Importing a placed DigiKey order acts on behalf of your account, so it needs a one-time
              authorization. Your DigiKey app's callback URL must be set to{' '}
              <code className="rounded bg-muted px-1 py-0.5 text-[11px]">{`${origin}/oauth/digikey/callback`}</code>.
            </p>
            {organization.digikey_account_connected ? (
              <div className="flex items-center justify-between gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
                <span className="flex items-center gap-2">
                  <CircleCheck className="size-4 shrink-0" />
                  DigiKey account connected.
                </span>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => router.delete('/oauth/digikey', { preserveScroll: true })}
                >
                  Disconnect
                </Button>
              </div>
            ) : (
              <Button asChild type="button" variant="outline" size="sm" disabled={!organization.digikey_configured}>
                <a href="/oauth/digikey/authorize">
                  <Plug className="size-4" />
                  Connect DigiKey account
                </a>
              </Button>
            )}
            {!organization.digikey_configured && (
              <p className="mt-2 text-xs text-muted-foreground">Save your Client ID and Secret first.</p>
            )}
          </div>
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          {organization.digikey_configured && (
            <Button type="button" variant="outline" onClick={() => removeProvider('remove_digikey')} disabled={form.processing}>
              Remove credentials
            </Button>
          )}
          <Button
            type="submit"
            disabled={
              form.processing ||
              !form.data.organization.digikey_client_id.trim() ||
              !form.data.organization.digikey_client_secret.trim()
            }
          >
            Save
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>LCSC Electronics</CardTitle>
          <CardDescription>
            Fetch a component's details, datasheet and image from LCSC by part number or LCSC code (e.g. C2040)
            when adding a part. No account or key needed.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center justify-between gap-4">
            <div>
              <div className="text-sm font-medium">Search LCSC</div>
              <div className="text-xs text-muted-foreground">
                Turning it on sets up an “LCSC” supplier (if it doesn’t exist yet) so looked-up part numbers link to it.
              </div>
            </div>
            <Switch
              aria-label="Search LCSC"
              checked={organization.lcsc_enabled}
              onCheckedChange={toggleLcsc}
            />
          </div>
          <p className="text-xs text-muted-foreground">
            LCSC only offers its official API to approved partners, so this uses the search behind lcsc.com, which
            LCSC may change or block at any time. Prices are in US dollars: they only fill a part's unit price when
            your organization's currency is USD.
          </p>
        </CardContent>
      </Card>
    </form>
  )
}
