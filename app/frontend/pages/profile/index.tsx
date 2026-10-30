import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useState } from 'react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Check, Copy, MailWarning } from 'lucide-react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { t, intlLocale, LOCALES, LOCALE_NAMES, type Locale } from '@/lib/i18n'
import { roleLabel } from '@/lib/roles'
import { DeleteAccountCard } from '@/components/delete-account-card'

interface ProfileUser {
  firstname: string
  lastname: string
  email: string
  email_confirmed: boolean
  // A new sign-in email waiting for confirmation (the current one still applies).
  unconfirmed_email: string | null
  // UI language picked here; null follows the browser.
  locale: Locale | null
}

interface Invitation {
  id: number
  organization_name: string
  role: 'owner' | 'admin' | 'member' | 'viewer'
  invited_by: string | null
  sent_at: string
}

interface NotificationMembership {
  id: number
  organization_name: string
  email_notifications: boolean
}

// An MCP client (Claude…) the user granted access to an organization:
// read-only, or allowed to change the inventory (write).
interface ConnectedApp {
  id: number
  name: string
  organization_name: string
  connected_at: string
  last_used_at: string | null
  write: boolean
  // False for a viewer of that organization: changes can't be turned on.
  can_write: boolean
}

interface PageProps {
  user: ProfileUser
  invitations: Invitation[]
  email_notifications_available: boolean
  notification_memberships: NotificationMembership[]
  mcp_url: string
  connected_apps: ConnectedApp[]
  // Organizations the user is the only owner of while others use them.
  deletion_blocked_by: string[]
}

export default function Profile({
  user, invitations, email_notifications_available, notification_memberships, mcp_url, connected_apps, deletion_blocked_by,
}: PageProps) {
  const [copied, setCopied] = useState(false)
  const copyMcpUrl = () => {
    navigator.clipboard?.writeText(mcp_url).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  const detailsForm = useForm({
    user: {
      firstname: user.firstname,
      lastname: user.lastname,
      email: user.email,
      // Only sent (and required) when the email changes — see ProfilesController.
      current_password: '',
    },
  })
  const emailChanged = detailsForm.data.user.email.trim().toLowerCase() !== user.email.toLowerCase()

  const passwordForm = useForm({
    user: {
      current_password: '',
      password: '',
      password_confirmation: '',
    },
  })

  const submitDetails = (e: FormEvent) => {
    e.preventDefault()
    detailsForm.patch('/profile', {
      preserveScroll: true,
      onFinish: () => detailsForm.setData('user', { ...detailsForm.data.user, current_password: '' }),
    })
  }

  const submitPassword = (e: FormEvent) => {
    e.preventDefault()
    passwordForm.patch('/profile', {
      preserveScroll: true,
      onSuccess: () => passwordForm.reset(),
    })
  }

  return (
    <AppLayout header={<PageHeader title={t('Profile')} subtitle={t('Your personal account settings')} />}>
      <Head title={t('Profile')} />

      <div className="mx-auto w-full min-w-0 max-w-[680px] space-y-6">
        <FlashMessages />

        {/* Email confirmation still owed: invitations stay hidden until then */}
        {(!user.email_confirmed || user.unconfirmed_email) && (
          <Alert>
            <MailWarning />
            <AlertTitle>
              {user.unconfirmed_email ? t('Confirm {email}', { email: user.unconfirmed_email }) : t('Confirm your email address')}
            </AlertTitle>
            <AlertDescription>
              <p>
                {user.unconfirmed_email
                  ? t('You\'ll keep signing in with {email} until you open the link we sent to {new_email}.', { email: user.email, new_email: user.unconfirmed_email })
                  : t('Open the link we sent to {email}. Invitations to join an organization appear here once your address is confirmed.', { email: user.email })}
              </p>
              <Button
                variant="outline"
                size="sm"
                className="mt-2"
                onClick={() => router.post('/confirm-email', {}, { preserveScroll: true })}
              >
                {t('Resend confirmation email')}
              </Button>
            </AlertDescription>
          </Alert>
        )}

        {/* Pending organization invitations */}
        {invitations.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle>{t('Invitations')}</CardTitle>
              <CardDescription>{t('You\'ll only join an organization once you accept its invitation.')}</CardDescription>
            </CardHeader>
            <CardContent className="divide-y">
              {invitations.map((invitation) => (
                <div key={invitation.id} className="flex flex-wrap items-center gap-3 py-3 first:pt-0 last:pb-0">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 font-semibold">
                      <span className="truncate">{invitation.organization_name}</span>
                      <Badge variant="outline">{roleLabel(invitation.role)}</Badge>
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {invitation.invited_by
                        ? t('Invited by {name} on {date}', { name: invitation.invited_by, date: new Date(invitation.sent_at).toLocaleDateString(intlLocale()) })
                        : t('Invited on {date}', { date: new Date(invitation.sent_at).toLocaleDateString(intlLocale()) })}
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => router.delete(`/invitations/${invitation.id}/decline`, { preserveScroll: true })}
                    >
                      {t('Decline')}
                    </Button>
                    <Button size="sm" onClick={() => router.post(`/invitations/${invitation.id}/accept`)}>
                      {t('Accept')}
                    </Button>
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        )}

        {/* Personal information */}
        <form onSubmit={submitDetails}>
          <Card>
            <CardHeader>
              <CardTitle>{t('Personal information')}</CardTitle>
              <CardDescription>{t('Your name and the email you sign in with.')}</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
              <Field>
                <FieldLabel>
                  <Label htmlFor="firstname">{t('First name')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="firstname"
                    value={detailsForm.data.user.firstname}
                    onChange={(e) => detailsForm.setData('user', { ...detailsForm.data.user, firstname: e.target.value })}
                    autoComplete="given-name"
                    aria-invalid={!!detailsForm.errors['user.firstname']}
                  />
                </FieldContent>
                {detailsForm.errors['user.firstname'] && <FieldError>{detailsForm.errors['user.firstname']}</FieldError>}
              </Field>

              <Field>
                <FieldLabel>
                  <Label htmlFor="lastname">{t('Last name')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="lastname"
                    value={detailsForm.data.user.lastname}
                    onChange={(e) => detailsForm.setData('user', { ...detailsForm.data.user, lastname: e.target.value })}
                    autoComplete="family-name"
                    aria-invalid={!!detailsForm.errors['user.lastname']}
                  />
                </FieldContent>
                {detailsForm.errors['user.lastname'] && <FieldError>{detailsForm.errors['user.lastname']}</FieldError>}
              </Field>

              <Field className="sm:col-span-2">
                <FieldLabel>
                  <Label htmlFor="email">{t('Email')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="email"
                    type="email"
                    value={detailsForm.data.user.email}
                    onChange={(e) => detailsForm.setData('user', { ...detailsForm.data.user, email: e.target.value })}
                    autoComplete="email"
                    aria-invalid={!!detailsForm.errors['user.email']}
                  />
                </FieldContent>
                {detailsForm.errors['user.email'] && <FieldError>{detailsForm.errors['user.email']}</FieldError>}
              </Field>

              {(emailChanged || detailsForm.errors['user.current_password']) && (
                <Field className="sm:col-span-2">
                  <FieldLabel>
                    <Label htmlFor="details_current_password">{t('Current password')}</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="details_current_password"
                      type="password"
                      value={detailsForm.data.user.current_password}
                      onChange={(e) => detailsForm.setData('user', { ...detailsForm.data.user, current_password: e.target.value })}
                      autoComplete="current-password"
                      aria-invalid={!!detailsForm.errors['user.current_password']}
                    />
                  </FieldContent>
                  <p className="text-sm text-muted-foreground">{t('Confirm your password to change the email you sign in with.')}</p>
                  {detailsForm.errors['user.current_password'] && <FieldError>{detailsForm.errors['user.current_password']}</FieldError>}
                </Field>
              )}
            </CardContent>
            <CardFooter className="justify-end border-t">
              <Button type="submit" disabled={detailsForm.processing}>
                {t('Save changes')}
              </Button>
            </CardFooter>
          </Card>
        </form>

        {/* UI language: English, French, or whatever the browser asks for */}
        <Card>
          <CardHeader>
            <CardTitle>{t('Language')}</CardTitle>
            <CardDescription>{t('The language of the interface and of the emails you receive.')}</CardDescription>
          </CardHeader>
          <CardContent>
            <Select
              value={user.locale ?? 'auto'}
              onValueChange={(value) => router.patch(
                '/profile/locale',
                { locale: value === 'auto' ? '' : value },
                { preserveScroll: true },
              )}
            >
              <SelectTrigger className="w-64" aria-label={t('Language')}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="auto">{t('Same as the browser')}</SelectItem>
                {LOCALES.map((locale) => (
                  <SelectItem key={locale} value={locale}>{LOCALE_NAMES[locale]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </CardContent>
        </Card>

        {/* Email notifications: a per-organization opt-out of the alert digest */}
        {email_notifications_available && notification_memberships.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle>{t('Email notifications')}</CardTitle>
              <CardDescription>
                {t('Low-stock and late-order digests, as each organization\'s admins set them up.')}
              </CardDescription>
            </CardHeader>
            <CardContent className="divide-y">
              {notification_memberships.map((membership) => (
                <div key={membership.id} className="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0">
                  <Label htmlFor={`notifications_${membership.id}`} className="min-w-0 truncate">
                    {membership.organization_name}
                  </Label>
                  <Switch
                    id={`notifications_${membership.id}`}
                    checked={membership.email_notifications}
                    onCheckedChange={(checked) => router.patch(
                      `/profile/notifications/${membership.id}`,
                      { email_notifications: checked },
                      { preserveScroll: true },
                    )}
                  />
                </div>
              ))}
            </CardContent>
          </Card>
        )}

        {/* MCP server: connect Claude (or another MCP client) to the inventory */}
        <Card>
          <CardHeader>
            <CardTitle>{t('Claude & AI assistants')}</CardTitle>
            <CardDescription>
              {t('Add this URL as a custom connector in Claude (or any MCP client) to ask about parts, stock and projects. You\'ll pick an organization, and whether the assistant may also change the inventory.')}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex gap-2">
              <Input readOnly value={mcp_url} className="font-mono" aria-label={t('MCP server URL')} onFocus={(e) => e.target.select()} />
              <Button variant="outline" size="icon" onClick={copyMcpUrl} aria-label={t('Copy MCP server URL')}>
                {copied ? <Check /> : <Copy />}
              </Button>
            </div>

            {connected_apps.length > 0 && (
              <div className="divide-y border-t">
                {connected_apps.map((app) => (
                  <div key={app.id} className="flex flex-wrap items-center gap-3 py-3 last:pb-0">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 font-semibold">
                        <span className="truncate">{app.name}</span>
                        <Badge variant="outline">{app.organization_name}</Badge>
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {t('Connected on {date}', { date: new Date(app.connected_at).toLocaleDateString(intlLocale()) })}
                        {app.last_used_at && t(' · last used {date}', { date: new Date(app.last_used_at).toLocaleString(intlLocale()) })}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Switch
                        id={`connected_app_write_${app.id}`}
                        checked={app.write && app.can_write}
                        disabled={!app.can_write}
                        onCheckedChange={(checked) => router.patch(`/profile/connected_apps/${app.id}`, { write: checked }, { preserveScroll: true })}
                      />
                      <Label htmlFor={`connected_app_write_${app.id}`} className="text-sm font-normal">
                        {app.can_write ? t('Allow changes') : t('Read-only (viewer)')}
                      </Label>
                    </div>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => router.delete(`/profile/connected_apps/${app.id}`, { preserveScroll: true })}
                    >
                      {t('Disconnect')}
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Password */}
        <form onSubmit={submitPassword}>
          <Card>
            <CardHeader>
              <CardTitle>{t('Password')}</CardTitle>
              <CardDescription>{t('Enter your current password to set a new one.')}</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
              <Field className="sm:col-span-2">
                <FieldLabel>
                  <Label htmlFor="current_password">{t('Current password')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="current_password"
                    type="password"
                    value={passwordForm.data.user.current_password}
                    onChange={(e) => passwordForm.setData('user', { ...passwordForm.data.user, current_password: e.target.value })}
                    autoComplete="current-password"
                    aria-invalid={!!passwordForm.errors['user.current_password']}
                  />
                </FieldContent>
                {passwordForm.errors['user.current_password'] && <FieldError>{passwordForm.errors['user.current_password']}</FieldError>}
              </Field>

              <Field>
                <FieldLabel>
                  <Label htmlFor="password">{t('New password')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="password"
                    type="password"
                    value={passwordForm.data.user.password}
                    onChange={(e) => passwordForm.setData('user', { ...passwordForm.data.user, password: e.target.value })}
                    autoComplete="new-password"
                    aria-invalid={!!passwordForm.errors['user.password']}
                  />
                </FieldContent>
                {passwordForm.errors['user.password'] && <FieldError>{passwordForm.errors['user.password']}</FieldError>}
              </Field>

              <Field>
                <FieldLabel>
                  <Label htmlFor="password_confirmation">{t('Confirm new password')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="password_confirmation"
                    type="password"
                    value={passwordForm.data.user.password_confirmation}
                    onChange={(e) => passwordForm.setData('user', { ...passwordForm.data.user, password_confirmation: e.target.value })}
                    autoComplete="new-password"
                    aria-invalid={!!passwordForm.errors['user.password_confirmation']}
                  />
                </FieldContent>
                {passwordForm.errors['user.password_confirmation'] && <FieldError>{passwordForm.errors['user.password_confirmation']}</FieldError>}
              </Field>
            </CardContent>
            <CardFooter className="justify-end border-t">
              <Button type="submit" disabled={passwordForm.processing}>
                {t('Update password')}
              </Button>
            </CardFooter>
          </Card>
        </form>

        <DeleteAccountCard blockedBy={deletion_blocked_by} />
      </div>
    </AppLayout>
  )
}
