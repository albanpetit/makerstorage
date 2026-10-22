import { Head, useForm, Link } from '@inertiajs/react'
import { FormEventHandler } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { Checkbox } from '@/components/ui/checkbox'
import { FlashMessages } from '@/components/flash-messages'
import { AuthLayout } from '@/components/auth-layout'
import { t } from '@/lib/i18n'

export default function Login() {
  const { data, setData, post, processing, errors } = useForm({
    user: {
      email: '',
      password: '',
    },
    remember_me: false,
  })

  const submit: FormEventHandler = (e) => {
    e.preventDefault()
    post('/login')
  }

  return (
    <>
      <Head title={t('Log in')} />

      <AuthLayout
        eyebrow={t('Stock management')}
        headline={t('Every resistor has its place, every withdrawal tracked.')}
        description={t('Component inventory, physical storage locations, stock movements, and restock alerts — all in one place.')}
      >
        <FlashMessages errors={errors} className="mb-6" />

        <div className="mb-6">
          <h2 className="text-2xl font-semibold tracking-tight">{t('Welcome back')}</h2>
          <p className="text-muted-foreground mt-1 text-sm">{t('Log in to access your inventory.')}</p>
        </div>

        <form onSubmit={submit}>
          <FieldGroup>
            <Field>
              <FieldLabel>
                <Label htmlFor="email">{t('Email address')}</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  id="email"
                  type="email"
                  placeholder={t('you@workshop.io')}
                  value={data.user.email}
                  onChange={(e) => setData('user', { ...data.user, email: e.target.value })}
                  required
                  autoFocus
                  autoComplete="email"
                  aria-invalid={!!errors['user.email']}
                />
              </FieldContent>
              {errors['user.email'] && <FieldError>{errors['user.email']}</FieldError>}
            </Field>

            <Field>
              <div className="flex items-center">
                <FieldLabel className="flex">
                  <Label htmlFor="password">{t('Password')}</Label>
                </FieldLabel>
                <Link
                  href="/forgot-password"
                  className="text-muted-foreground hover:text-foreground ml-auto text-xs transition-colors"
                >
                  {t('Forgot password?')}
                </Link>
              </div>
              <FieldContent>
                <Input
                  id="password"
                  type="password"
                  placeholder="••••••••"
                  value={data.user.password}
                  onChange={(e) => setData('user', { ...data.user, password: e.target.value })}
                  required
                  autoComplete="current-password"
                  aria-invalid={!!errors['user.password']}
                />
              </FieldContent>
              {errors['user.password'] && <FieldError>{errors['user.password']}</FieldError>}
            </Field>

            <div className="flex items-center gap-2">
              <Checkbox
                id="remember_me"
                checked={data.remember_me}
                onCheckedChange={(checked) => setData('remember_me', checked === true)}
              />
              <Label htmlFor="remember_me" className="text-muted-foreground cursor-pointer text-sm font-normal">
                {t('Stay logged in on this device')}
              </Label>
            </div>

            <Button type="submit" className="mt-1 w-full" disabled={processing}>
              {processing ? t('Logging in...') : t('Log in')}
            </Button>
          </FieldGroup>
        </form>

        <div className="mt-6 text-center text-sm">
          <span className="text-muted-foreground">{t('Don\'t have an account?')} </span>
          <Link href="/signup" className="font-medium underline underline-offset-4">
            {t('Sign up')}
          </Link>
        </div>
      </AuthLayout>
    </>
  )
}
