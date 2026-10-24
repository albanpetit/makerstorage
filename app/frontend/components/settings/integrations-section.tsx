import { FormEvent } from 'react'
import { router } from '@inertiajs/react'
import { Plug, CircleCheck } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'

import type { IntegrationsForm, OrganizationSettings } from './types'
import { t, tx } from '@/lib/i18n'

interface IntegrationsSectionProps {
  form: IntegrationsForm
  organization: OrganizationSettings
}

// Mouser, DigiKey and GitHub credentials (write-only), the DigiKey account
// link, and the LCSC switch (no key: LCSC's catalog is queried without an account).
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
    github_token: '',
    remove_github_token: false,
    anthropic_api_key: '',
    remove_anthropic_api_key: false,
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
  const removeProvider = (flag: 'remove_mouser_api_key' | 'remove_mouser_order_api_key' | 'remove_digikey' | 'remove_github_token' | 'remove_anthropic_api_key') => {
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

  // The model saves straight away too, like the LCSC switch.
  const chooseAiModel = (model: string) => {
    router.patch('/settings', { organization: { ai_model: model } }, { preserveScroll: true })
  }

  return (
    <form onSubmit={submitIntegrations} className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">{t('Integrations')}</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          {t('Connect external supplier catalogs to look up component data by part number, GitHub to fetch projects\' KiCad files, and Claude to fill in parts from photos and datasheets.')}
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{t('Mouser Electronics')}</CardTitle>
          <CardDescription>
            {tx('Fetch a component\'s details, datasheet and image from Mouser when adding a part. Create a free API key from the {link}.', {
              link: (
                <a
                  href="https://www.mouser.com/api-hub/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-primary underline underline-offset-2"
                >
                  {t('Mouser API Hub')}
                </a>
              ),
            })}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {organization.mouser_api_key_present && (
            <div className="flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
              <CircleCheck className="size-4 shrink-0" />
              {t('An API key is configured. Enter a new key below to replace it.')}
            </div>
          )}
          <Field>
            <FieldLabel><Label>{t('API key')}</Label></FieldLabel>
            <FieldContent>
              <Input
                type="password"
                autoComplete="off"
                placeholder={organization.mouser_api_key_present ? '••••••••••••••••' : t('Paste your Mouser API key')}
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
            {t('Saving a key sets up a “Mouser Electronics” supplier (if it doesn’t exist yet) so looked-up prices fill in automatically when you add parts.')}
          </p>

          <div className="border-t pt-4">
            {organization.mouser_order_api_key_present && (
              <div className="mb-3 flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
                <CircleCheck className="size-4 shrink-0" />
                {t('An Order API key is configured. Enter a new key below to replace it.')}
              </div>
            )}
            <Field>
              <FieldLabel><Label>{t('Order API key')}</Label></FieldLabel>
              <FieldContent>
                <Input
                  type="password"
                  autoComplete="off"
                  placeholder={organization.mouser_order_api_key_present ? '••••••••••••••••' : t('Paste your Mouser Order API key')}
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
              {t('A separate key (from the same API Hub) enables pushing an order to a Mouser cart and importing a placed Mouser order. Optional.')}
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
                {t('Remove order key')}
              </Button>
            )}
          </div>
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          {organization.mouser_api_key_present && (
            <Button type="button" variant="outline" onClick={() => removeProvider('remove_mouser_api_key')} disabled={form.processing}>
              {t('Remove key')}
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
            {t('Save')}
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('DigiKey Electronics')}</CardTitle>
          <CardDescription>
            {tx('Fetch a component\'s details, datasheet and image from DigiKey when adding a part. Create an app to get a Client ID and Secret from the {link}.', {
              link: (
                <a
                  href="https://developer.digikey.com/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-primary underline underline-offset-2"
                >
                  {t('DigiKey developer portal')}
                </a>
              ),
            })}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {organization.digikey_configured && (
            <div className="flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
              <CircleCheck className="size-4 shrink-0" />
              {t('Credentials are configured. Enter new values below to replace them.')}
            </div>
          )}
          <Field>
            <FieldLabel><Label>{t('Client ID')}</Label></FieldLabel>
            <FieldContent>
              <Input
                type="password"
                autoComplete="off"
                placeholder={organization.digikey_configured ? '••••••••••••••••' : t('Paste your DigiKey Client ID')}
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
            <FieldLabel><Label>{t('Client Secret')}</Label></FieldLabel>
            <FieldContent>
              <Input
                type="password"
                autoComplete="off"
                placeholder={organization.digikey_configured ? '••••••••••••••••' : t('Paste your DigiKey Client Secret')}
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
            {t('Saving credentials sets up a “DigiKey” supplier (if it doesn’t exist yet) so looked-up prices fill in automatically when you add parts.')}
          </p>

          <div className="border-t pt-4">
            <Label>{t('Order import')}</Label>
            <p className="mt-1 mb-3 text-xs text-muted-foreground">
              {tx('Importing a placed DigiKey order acts on behalf of your account, so it needs a one-time authorization. Your DigiKey app\'s callback URL must be set to {url}.', {
                url: <code className="rounded bg-muted px-1 py-0.5 text-[11px]">{`${origin}/oauth/digikey/callback`}</code>,
              })}
            </p>
            {organization.digikey_account_connected ? (
              <div className="flex items-center justify-between gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
                <span className="flex items-center gap-2">
                  <CircleCheck className="size-4 shrink-0" />
                  {t('DigiKey account connected.')}
                </span>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => router.delete('/oauth/digikey', { preserveScroll: true })}
                >
                  {t('Disconnect')}
                </Button>
              </div>
            ) : (
              <Button asChild type="button" variant="outline" size="sm" disabled={!organization.digikey_configured}>
                <a href="/oauth/digikey/authorize">
                  <Plug className="size-4" />
                  {t('Connect DigiKey account')}
                </a>
              </Button>
            )}
            {!organization.digikey_configured && (
              <p className="mt-2 text-xs text-muted-foreground">{t('Save your Client ID and Secret first.')}</p>
            )}
          </div>
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          {organization.digikey_configured && (
            <Button type="button" variant="outline" onClick={() => removeProvider('remove_digikey')} disabled={form.processing}>
              {t('Remove credentials')}
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
            {t('Save')}
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>LCSC Electronics</CardTitle>
          <CardDescription>
            {t('Fetch a component\'s details, datasheet and image from LCSC by part number or LCSC code (e.g. C2040) when adding a part. No account or key needed.')}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center justify-between gap-4">
            <div>
              <div className="text-sm font-medium">{t('Search LCSC')}</div>
              <div className="text-xs text-muted-foreground">
                {t('Turning it on sets up an “LCSC” supplier (if it doesn’t exist yet) so looked-up part numbers link to it.')}
              </div>
            </div>
            <Switch
              aria-label={t('Search LCSC')}
              checked={organization.lcsc_enabled}
              onCheckedChange={toggleLcsc}
            />
          </div>
          <p className="text-xs text-muted-foreground">
            {t('LCSC only offers its official API to approved partners, so this uses the search behind lcsc.com, which LCSC may change or block at any time. Prices are in US dollars: they only fill a part\'s unit price when your organization\'s currency is USD.')}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>GitHub</CardTitle>
          <CardDescription>
            {tx('Projects can be linked to a GitHub repository to fetch their KiCad files and BOM. Public repositories work without a token. For private ones (or to lift GitHub\'s limit of 60 requests an hour), create a {link} with read-only access to the repositories\' contents.', {
              link: (
                <a
                  href="https://github.com/settings/personal-access-tokens/new"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-primary underline underline-offset-2"
                >
                  {t('fine-grained personal access token')}
                </a>
              ),
            })}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {organization.github_token_present && (
            <div className="flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
              <CircleCheck className="size-4 shrink-0" />
              {t('A token is configured. Enter a new token below to replace it.')}
            </div>
          )}
          <Field>
            <FieldLabel><Label>{t('Personal access token')}</Label></FieldLabel>
            <FieldContent>
              <Input
                type="password"
                autoComplete="off"
                placeholder={organization.github_token_present ? '••••••••••••••••' : 'github_pat_…'}
                value={form.data.organization.github_token}
                onChange={(e) => form.setData('organization', {
                  ...form.data.organization,
                  github_token: e.target.value,
                })}
              />
            </FieldContent>
            {form.errors['organization.github_token'] && (
              <FieldError>{form.errors['organization.github_token']}</FieldError>
            )}
          </Field>
          <p className="text-xs text-muted-foreground">
            {t('The token is shared by every project of this organization and only ever sent to api.github.com.')}
          </p>
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          {organization.github_token_present && (
            <Button type="button" variant="outline" onClick={() => removeProvider('remove_github_token')} disabled={form.processing}>
              {t('Remove token')}
            </Button>
          )}
          <Button type="submit" disabled={form.processing || !form.data.organization.github_token.trim()}>
            {t('Save')}
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('Claude (AI-assisted entry)')}</CardTitle>
          <CardDescription>
            {tx('Fill in a new part from a photo of it or its bag label, or from its datasheet: Claude reads the files and prefills the form. Uses your organization\'s own Anthropic API key, created in the {link}, and billed to it.', {
              link: (
                <a
                  href="https://console.anthropic.com/settings/keys"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-primary underline underline-offset-2"
                >
                  {t('Claude Console')}
                </a>
              ),
            })}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {organization.anthropic_api_key_present && (
            <div className="flex items-center gap-2 rounded-md border border-green-600/30 bg-green-600/10 px-3 py-2 text-sm text-green-700 dark:text-green-400">
              <CircleCheck className="size-4 shrink-0" />
              {t('A key is configured: “Fill in with AI” shows in the add-part dialog. Enter a new key below to replace it.')}
            </div>
          )}
          <Field>
            <FieldLabel><Label htmlFor="anthropic-api-key">{t('Anthropic API key')}</Label></FieldLabel>
            <FieldContent>
              <Input
                id="anthropic-api-key"
                type="password"
                autoComplete="off"
                placeholder={organization.anthropic_api_key_present ? '••••••••••••••••' : 'sk-ant-…'}
                value={form.data.organization.anthropic_api_key}
                onChange={(e) => form.setData('organization', {
                  ...form.data.organization,
                  anthropic_api_key: e.target.value,
                })}
              />
            </FieldContent>
            {form.errors['organization.anthropic_api_key'] && (
              <FieldError>{form.errors['organization.anthropic_api_key']}</FieldError>
            )}
          </Field>
          <Field>
            <FieldLabel><Label htmlFor="ai-model">{t('Model')}</Label></FieldLabel>
            <FieldContent>
              <Select value={organization.ai_model} onValueChange={chooseAiModel}>
                <SelectTrigger id="ai-model" className="w-full sm:w-64">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {organization.ai_models.map((model) => (
                    <SelectItem key={model.value} value={model.value}>{model.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FieldContent>
          </Field>
          <p className="text-xs text-muted-foreground">
            {t('Opus reads small print and datasheets best; Sonnet and Haiku cost less per read. The files go to Anthropic only when a member clicks Read, and the answer is never saved without their review.')}
          </p>
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          {organization.anthropic_api_key_present && (
            <Button type="button" variant="outline" onClick={() => removeProvider('remove_anthropic_api_key')} disabled={form.processing}>
              {t('Remove key')}
            </Button>
          )}
          <Button type="submit" disabled={form.processing || !form.data.organization.anthropic_api_key.trim()}>
            {t('Save')}
          </Button>
        </CardFooter>
      </Card>
    </form>
  )
}
