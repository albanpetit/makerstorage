import { Head, useForm, Link } from '@inertiajs/react'
import { FormEventHandler } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { FlashMessages } from '@/components/flash-messages'

import authImage from '/assets/auth.jpeg'

interface ResetPasswordProps {
  reset_password_token: string
}

export default function ResetPassword({ reset_password_token }: ResetPasswordProps) {
  const { data, setData, put, processing, errors } = useForm({
    user: {
      password: '',
      password_confirmation: '',
      reset_password_token: reset_password_token,
    },
  })

  const submit: FormEventHandler = (e) => {
    e.preventDefault()
    put('/reset-password')
  }

  return (
    <>
      <Head title="Reset Password" />

      <div className="grid min-h-svh lg:grid-cols-2 bg-background text-foreground">
        <div className="flex flex-col gap-4 p-6 md:p-10 bg-background text-foreground">
          <div className="flex flex-1 items-center justify-center">
            <div className="w-full max-w-xs">
              <FlashMessages errors={errors} />

              <form onSubmit={submit} className="space-y-4 mt-4">
                <FieldGroup>
                  <div className="flex flex-col items-center gap-1 text-center">
                    <h1 className="text-2xl font-bold">Reset your password</h1>
                    <p className="text-muted-foreground text-sm text-balance">
                      Enter your new password below
                    </p>
                  </div>

                  {/* Password Field */}
                  <Field>
                    <FieldLabel>
                      <Label htmlFor="password">New Password</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        id="password"
                        type="password"
                        value={data.user.password}
                        onChange={(e) => setData('user', { ...data.user, password: e.target.value })}
                        required
                        autoFocus
                        autoComplete="new-password"
                        aria-invalid={!!errors['user.password']}
                      />
                    </FieldContent>
                    {errors['user.password'] && <FieldError>{errors['user.password']}</FieldError>}
                  </Field>

                  {/* Password Confirmation Field */}
                  <Field>
                    <FieldLabel>
                      <Label htmlFor="password_confirmation">Confirm Password</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        id="password_confirmation"
                        type="password"
                        value={data.user.password_confirmation}
                        onChange={(e) => setData('user', { ...data.user, password_confirmation: e.target.value })}
                        required
                        autoComplete="new-password"
                        aria-invalid={!!errors['user.password_confirmation']}
                      />
                    </FieldContent>
                    {errors['user.password_confirmation'] && <FieldError>{errors['user.password_confirmation']}</FieldError>}
                  </Field>

                  {/* Submit Button */}
                  <Button
                    type="submit"
                    className="w-full"
                    disabled={processing}
                  >
                    {processing ? 'Resetting...' : 'Reset password'}
                  </Button>

                  {/* Back to login link */}
                  <div className="text-center text-sm">
                    <span className="text-muted-foreground">Remember your password? </span>
                    <Link
                      href="/login"
                      className="text-foreground hover:text-primary transition-colors underline-offset-4 hover:underline font-medium"
                    >
                      Back to login
                    </Link>
                  </div>
                </FieldGroup>
              </form>
            </div>
          </div>
        </div>
        <div className="relative hidden lg:block">
          <img
            src={authImage}
            alt="Image"
            className="absolute inset-0 h-full w-full object-cover dark:brightness-[0.8]"
          />
        </div>
      </div>
    </>
  )
}
