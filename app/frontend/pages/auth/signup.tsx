import { Head, useForm, Link } from '@inertiajs/react'
import { FormEventHandler } from 'react'
import { Users } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldGroup, FieldLabel, FieldDescription } from '@/components/ui/field'
import { FlashMessages } from '@/components/flash-messages'
import { AuthLayout } from '@/components/auth-layout'

export default function Signup() {
  const { data, setData, post, processing, errors } = useForm({
    user: {
      firstname: '',
      lastname: '',
      email: '',
      password: '',
      password_confirmation: '',
    },
  })

  const submit: FormEventHandler = (e) => {
    e.preventDefault()
    post('/signup')
  }

  return (
    <>
      <Head title="Sign up" />

      <AuthLayout
        eyebrow="Stock management"
        headline="Every resistor has its place, every withdrawal tracked."
        description="Component inventory, physical storage locations, stock movements, and restock alerts — all in one place."
      >
        <FlashMessages errors={errors} className="mb-6" />

        <div className="mb-6">
          <h2 className="text-2xl font-semibold tracking-tight">Create an account</h2>
          <p className="text-muted-foreground mt-1 text-sm">Start managing your component inventory.</p>
        </div>

        <form onSubmit={submit}>
          <FieldGroup>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label htmlFor="firstname">First name</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="firstname"
                    type="text"
                    value={data.user.firstname}
                    onChange={(e) => setData('user', { ...data.user, firstname: e.target.value })}
                    required
                    autoFocus
                    autoComplete="given-name"
                    aria-invalid={!!errors['user.firstname']}
                  />
                </FieldContent>
                {errors['user.firstname'] && <FieldError>{errors['user.firstname']}</FieldError>}
              </Field>

              <Field>
                <FieldLabel>
                  <Label htmlFor="lastname">Last name</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    id="lastname"
                    type="text"
                    value={data.user.lastname}
                    onChange={(e) => setData('user', { ...data.user, lastname: e.target.value })}
                    required
                    autoComplete="family-name"
                    aria-invalid={!!errors['user.lastname']}
                  />
                </FieldContent>
                {errors['user.lastname'] && <FieldError>{errors['user.lastname']}</FieldError>}
              </Field>
            </div>

            <Field>
              <FieldLabel>
                <Label htmlFor="email">Email address</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  id="email"
                  type="email"
                  placeholder="you@workshop.io"
                  value={data.user.email}
                  onChange={(e) => setData('user', { ...data.user, email: e.target.value })}
                  required
                  autoComplete="email"
                  aria-invalid={!!errors['user.email']}
                />
              </FieldContent>
              {errors['user.email'] && <FieldError>{errors['user.email']}</FieldError>}
            </Field>

            <Field>
              <FieldLabel>
                <Label htmlFor="password">Password</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  id="password"
                  type="password"
                  placeholder="••••••••"
                  value={data.user.password}
                  onChange={(e) => setData('user', { ...data.user, password: e.target.value })}
                  required
                  autoComplete="new-password"
                  aria-invalid={!!errors['user.password']}
                />
                <FieldDescription>At least 8 characters.</FieldDescription>
              </FieldContent>
              {errors['user.password'] && <FieldError>{errors['user.password']}</FieldError>}
            </Field>

            <Field>
              <FieldLabel>
                <Label htmlFor="password_confirmation">Confirm password</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  id="password_confirmation"
                  type="password"
                  placeholder="••••••••"
                  value={data.user.password_confirmation}
                  onChange={(e) => setData('user', { ...data.user, password_confirmation: e.target.value })}
                  required
                  autoComplete="new-password"
                  aria-invalid={!!errors['user.password_confirmation']}
                />
              </FieldContent>
              {errors['user.password_confirmation'] && (
                <FieldError>{errors['user.password_confirmation']}</FieldError>
              )}
            </Field>

            <div className="bg-muted flex items-start gap-2.5 rounded-lg p-3">
              <Users className="text-muted-foreground mt-0.5 size-4 shrink-0" />
              <p className="text-muted-foreground text-xs leading-relaxed">
                A personal organization is created automatically when you sign up. You can create additional
                organizations later to manage stock with a team.
              </p>
            </div>

            <Button type="submit" className="mt-1 w-full" disabled={processing}>
              {processing ? 'Creating account...' : 'Create account'}
            </Button>
          </FieldGroup>
        </form>

        <div className="mt-6 text-center text-sm">
          <span className="text-muted-foreground">Already have an account? </span>
          <Link href="/login" className="font-medium underline underline-offset-4">
            Log in
          </Link>
        </div>
      </AuthLayout>
    </>
  )
}
