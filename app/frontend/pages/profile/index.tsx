import { Head, useForm } from '@inertiajs/react'
import { FormEvent } from 'react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'

interface ProfileUser {
  firstname: string
  lastname: string
  email: string
}

interface PageProps {
  user: ProfileUser
}

export default function Profile({ user }: PageProps) {
  const detailsForm = useForm({
    user: {
      firstname: user.firstname,
      lastname: user.lastname,
      email: user.email,
    },
  })

  const passwordForm = useForm({
    user: {
      current_password: '',
      password: '',
      password_confirmation: '',
    },
  })

  const submitDetails = (e: FormEvent) => {
    e.preventDefault()
    detailsForm.patch('/profile', { preserveScroll: true })
  }

  const submitPassword = (e: FormEvent) => {
    e.preventDefault()
    passwordForm.patch('/profile', {
      preserveScroll: true,
      onSuccess: () => passwordForm.reset(),
    })
  }

  return (
    <AppLayout header={<PageHeader title="Profile" subtitle="Your personal account settings" />}>
      <Head title="Profile" />

      <div className="mx-auto w-full min-w-0 max-w-[680px] space-y-6">
        <FlashMessages />

        {/* Personal information */}
        <form onSubmit={submitDetails}>
          <Card>
            <CardHeader>
              <CardTitle>Personal information</CardTitle>
              <CardDescription>Your name and the email you sign in with.</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
              <Field>
                <FieldLabel>
                  <Label htmlFor="firstname">First name</Label>
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
                  <Label htmlFor="lastname">Last name</Label>
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
                  <Label htmlFor="email">Email</Label>
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
            </CardContent>
            <CardFooter className="justify-end border-t">
              <Button type="submit" disabled={detailsForm.processing}>
                Save changes
              </Button>
            </CardFooter>
          </Card>
        </form>

        {/* Password */}
        <form onSubmit={submitPassword}>
          <Card>
            <CardHeader>
              <CardTitle>Password</CardTitle>
              <CardDescription>Enter your current password to set a new one.</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
              <Field className="sm:col-span-2">
                <FieldLabel>
                  <Label htmlFor="current_password">Current password</Label>
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
                  <Label htmlFor="password">New password</Label>
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
                  <Label htmlFor="password_confirmation">Confirm new password</Label>
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
                Update password
              </Button>
            </CardFooter>
          </Card>
        </form>
      </div>
    </AppLayout>
  )
}
