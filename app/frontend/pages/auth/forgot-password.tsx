import { Head, useForm, Link } from '@inertiajs/react'
import { FormEventHandler } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { FlashMessages } from '@/components/flash-messages'

import authImage from '/assets/auth.jpeg'

export default function ForgotPassword() {
  const { data, setData, post, processing, errors } = useForm({
    user: {
      email: '',
    },
  })

  const submit: FormEventHandler = (e) => {
    e.preventDefault()
    post('/forgot-password')
  }

  return (
    <>
      <Head title="Forgot Password" />

      <div className="grid min-h-svh lg:grid-cols-2 bg-background text-foreground">
        <div className="flex flex-col gap-4 p-6 md:p-10 bg-background text-foreground">
          <div className="flex flex-1 items-center justify-center">
            <div className="w-full max-w-xs">
              <FlashMessages errors={errors} />

              <form onSubmit={submit} className="space-y-4 mt-4">
                <FieldGroup>
                  <div className="flex flex-col items-center gap-1 text-center">
                    <h1 className="text-2xl font-bold">Forgot your password?</h1>
                    <p className="text-muted-foreground text-sm text-balance">
                      Enter your email and we'll send you a link to reset your password
                    </p>
                  </div>

                  {/* Email Field */}
                  <Field>
                    <FieldLabel>
                      <Label htmlFor="email">Email</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        id="email"
                        type="email"
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

                  {/* Submit Button */}
                  <Button
                    type="submit"
                    className="w-full"
                    disabled={processing}
                  >
                    {processing ? 'Sending...' : 'Send reset link'}
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
