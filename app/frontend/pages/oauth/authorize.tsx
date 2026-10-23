import { Head, router } from '@inertiajs/react'
import { useState } from 'react'
import { ShieldAlert } from 'lucide-react'

import { AuthLayout } from '@/components/auth-layout'
import { FlashMessages } from '@/components/flash-messages'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Field, FieldContent, FieldLabel } from '@/components/ui/field'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { t, tx } from '@/lib/i18n'

interface Organization {
  id: number
  name: string
  // Viewers can't let the application change anything.
  can_write: boolean
}

interface PageProps {
  // Set instead of everything else when the request can't be trusted.
  error?: string
  client_name?: string
  redirect_host?: string
  loopback?: boolean
  mcp_url?: string
  organizations?: Organization[]
  default_organization_id?: number | null
  // The client asked for the mcp:write scope: "Allow changes" starts ticked.
  write_requested?: boolean
  request?: Record<string, string>
}

export default function OauthAuthorize({
  error, client_name, redirect_host, loopback, organizations = [], default_organization_id, write_requested = false, request = {},
}: PageProps) {
  const [organizationId, setOrganizationId] = useState(
    String(default_organization_id ?? organizations[0]?.id ?? ''),
  )
  const [allowChanges, setAllowChanges] = useState(write_requested)
  const [processing, setProcessing] = useState(false)
  const canWrite = organizations.find((organization) => String(organization.id) === organizationId)?.can_write ?? false
  const write = allowChanges && canWrite

  const decide = (decision: 'allow' | 'deny') => {
    router.post('/oauth/authorize', { ...request, decision, organization_id: organizationId, write }, {
      onStart: () => setProcessing(true),
      onFinish: () => setProcessing(false),
    })
  }

  return (
    <>
      <Head title={t('Connect an application')} />

      <AuthLayout
        eyebrow={t('Connect an application')}
        headline={t('Ask Claude what\'s on your shelves.')}
        description={t('Connected assistants can search parts, check stock and storage locations, and see whether a project or a BOM can be built. If you allow it, they can also record stock movements and create or edit parts and projects.')}
      >
        <FlashMessages className="mb-6" />

        {error ? (
          <Alert variant="destructive">
            <ShieldAlert />
            <AlertTitle>{t('This connection request can\'t be used')}</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        ) : (
          <>
            <div className="mb-6">
              <h2 className="text-2xl font-semibold tracking-tight">{t('Allow {name}?', { name: client_name ?? '' })}</h2>
              <p className="text-muted-foreground mt-1 text-sm">
                {tx('{name} wants access to the inventory of one of your organizations. You\'ll be sent back to {host}.', {
                  name: <span className="font-medium text-foreground">{client_name}</span>,
                  host: <span className="font-mono text-foreground">{redirect_host}</span>,
                })}
              </p>
            </div>

            {loopback && (
              <Alert className="mb-6">
                <ShieldAlert />
                <AlertTitle>{t('An application on your computer')}</AlertTitle>
                <AlertDescription>
                  {t('Only allow this if you just started the connection yourself, for example from Claude Code.')}
                </AlertDescription>
              </Alert>
            )}

            <Field className="mb-6">
              <FieldLabel>
                <Label>{t('Organization')}</Label>
              </FieldLabel>
              <FieldContent>
                <Select value={organizationId} onValueChange={setOrganizationId}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder={t('Select an organization')} />
                  </SelectTrigger>
                  <SelectContent>
                    {organizations.map((organization) => (
                      <SelectItem key={organization.id} value={String(organization.id)}>
                        {organization.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FieldContent>
            </Field>

            <div className="mb-6 flex items-start gap-2">
              <Checkbox
                id="allow_changes"
                className="mt-0.5"
                checked={write}
                disabled={!canWrite}
                onCheckedChange={(checked) => setAllowChanges(checked === true)}
              />
              <div className="grid gap-1">
                <Label htmlFor="allow_changes" className="cursor-pointer">{t('Allow changes')}</Label>
                <p className="text-muted-foreground text-xs">
                  {canWrite
                    ? t('Lets {name} add, remove, move and count stock, and create or edit parts and projects, in your name. Leave it off for read-only access.', { name: client_name ?? '' })
                    : t('You\'re a viewer in this organization, so the access will be read-only.')}
                </p>
              </div>
            </div>

            <div className="flex gap-2">
              <Button variant="outline" className="flex-1" disabled={processing} onClick={() => decide('deny')}>
                {t('Deny')}
              </Button>
              <Button className="flex-1" disabled={processing || !organizationId} onClick={() => decide('allow')}>
                {t('Allow access')}
              </Button>
            </div>

            <p className="text-muted-foreground mt-6 text-xs">
              {t('You can disconnect it at any time from your profile.')}
            </p>
          </>
        )}
      </AuthLayout>
    </>
  )
}
