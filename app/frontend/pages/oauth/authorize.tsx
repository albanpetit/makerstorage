import { Head, router } from '@inertiajs/react'
import { useState } from 'react'
import { ShieldAlert } from 'lucide-react'

import { AuthLayout } from '@/components/auth-layout'
import { FlashMessages } from '@/components/flash-messages'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldContent, FieldLabel } from '@/components/ui/field'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

interface Organization {
  id: number
  name: string
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
  request?: Record<string, string>
}

export default function OauthAuthorize({
  error, client_name, redirect_host, loopback, organizations = [], default_organization_id, request = {},
}: PageProps) {
  const [organizationId, setOrganizationId] = useState(
    String(default_organization_id ?? organizations[0]?.id ?? ''),
  )
  const [processing, setProcessing] = useState(false)

  const decide = (decision: 'allow' | 'deny') => {
    router.post('/oauth/authorize', { ...request, decision, organization_id: organizationId }, {
      onStart: () => setProcessing(true),
      onFinish: () => setProcessing(false),
    })
  }

  return (
    <>
      <Head title="Connect an application" />

      <AuthLayout
        eyebrow="Connect an application"
        headline="Ask Claude what's on your shelves."
        description="Connected assistants can search parts, check stock and storage locations, and see whether a project or a BOM can be built. They can't change anything."
      >
        <FlashMessages className="mb-6" />

        {error ? (
          <Alert variant="destructive">
            <ShieldAlert />
            <AlertTitle>This connection request can't be used</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        ) : (
          <>
            <div className="mb-6">
              <h2 className="text-2xl font-semibold tracking-tight">Allow {client_name}?</h2>
              <p className="text-muted-foreground mt-1 text-sm">
                <span className="font-medium text-foreground">{client_name}</span> wants read-only access to the
                inventory of one of your organizations. You'll be sent back to{' '}
                <span className="font-mono text-foreground">{redirect_host}</span>.
              </p>
            </div>

            {loopback && (
              <Alert className="mb-6">
                <ShieldAlert />
                <AlertTitle>An application on your computer</AlertTitle>
                <AlertDescription>
                  Only allow this if you just started the connection yourself, for example from Claude Code.
                </AlertDescription>
              </Alert>
            )}

            <Field className="mb-6">
              <FieldLabel>
                <Label>Organization</Label>
              </FieldLabel>
              <FieldContent>
                <Select value={organizationId} onValueChange={setOrganizationId}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Select an organization" />
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

            <div className="flex gap-2">
              <Button variant="outline" className="flex-1" disabled={processing} onClick={() => decide('deny')}>
                Deny
              </Button>
              <Button className="flex-1" disabled={processing || !organizationId} onClick={() => decide('allow')}>
                Allow access
              </Button>
            </div>

            <p className="text-muted-foreground mt-6 text-xs">
              You can disconnect it at any time from your profile.
            </p>
          </>
        )}
      </AuthLayout>
    </>
  )
}
