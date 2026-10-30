import { useState } from 'react'
import { router, usePage } from '@inertiajs/react'
import { Trash2 } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import { t } from '@/lib/i18n'

// Profile → Delete account (GDPR erasure). Organizations nobody else uses go
// with the account; one the user is the only owner of, with other members,
// must get another owner first (listed in `blockedBy`). Confirmed with the
// current password, which the server checks.
export function DeleteAccountCard({ blockedBy }: { blockedBy: string[] }) {
  const { legal } = usePage().props
  const [open, setOpen] = useState(false)
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)

  const submit = () => {
    router.delete('/profile', {
      data: { user: { current_password: password } },
      onStart: () => setProcessing(true),
      onFinish: () => setProcessing(false),
      onError: (errors) => setError([errors['user.current_password'] ?? []].flat()[0] ?? null),
    })
  }

  return (
    <Card className="border-destructive/40">
      <CardHeader>
        <CardTitle>{t('Delete account')}</CardTitle>
        <CardDescription>
          {t('Permanently deletes your account and the organizations only you use, with all their data. In organizations shared with others, your history stays but no longer shows your name.')}
          {legal?.privacy_policy_url && (
            <>
              {' '}
              <a href={legal.privacy_policy_url} target="_blank" rel="noreferrer" className="underline underline-offset-4">
                {t('Privacy policy')}
              </a>
            </>
          )}
        </CardDescription>
      </CardHeader>
      {blockedBy.length > 0 && (
        <CardContent className="text-sm text-muted-foreground">
          {t('You are the only owner of {organizations}, which other members use. Name another owner there first, or delete the organization.', {
            organizations: blockedBy.join(', '),
          })}
        </CardContent>
      )}
      <CardFooter className="justify-end border-t border-destructive/40">
        <AlertDialog
          open={open}
          onOpenChange={(next) => {
            setOpen(next)
            setPassword('')
            setError(null)
          }}
        >
          <AlertDialogTrigger asChild>
            <Button type="button" variant="destructive" disabled={blockedBy.length > 0}>
              <Trash2 className="size-4" /> {t('Delete account')}
            </Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <form
              className="grid gap-4"
              onSubmit={(e) => {
                e.preventDefault()
                submit()
              }}
            >
              <AlertDialogHeader>
                <AlertDialogTitle>{t('Delete your account?')}</AlertDialogTitle>
                <AlertDialogDescription>
                  {t('This cannot be undone. Download a backup of your organizations first if you may want their data back. To confirm, enter your password.')}
                </AlertDialogDescription>
              </AlertDialogHeader>
              <Field>
                <FieldLabel>
                  <Label htmlFor="delete_account_password">{t('Current password')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="delete_account_password"
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    autoComplete="current-password"
                    autoFocus
                    aria-invalid={!!error}
                  />
                </FieldContent>
                {error && <FieldError>{error}</FieldError>}
              </Field>
              <AlertDialogFooter>
                <AlertDialogCancel type="button">{t('Cancel')}</AlertDialogCancel>
                <Button type="submit" variant="destructive" disabled={!password || processing}>
                  <Trash2 className="size-4" /> {t('Delete account')}
                </Button>
              </AlertDialogFooter>
            </form>
          </AlertDialogContent>
        </AlertDialog>
      </CardFooter>
    </Card>
  )
}
