import { Head, useForm, Link } from '@inertiajs/react'
import { FormEventHandler } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { FlashMessages } from '@/components/flash-messages'

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

      <div className="grid min-h-svh lg:grid-cols-2 bg-background text-foreground">
        <div className="flex flex-col gap-4 p-6 md:p-10 bg-background text-foreground">
          <div className="flex flex-1 items-center justify-center">
            <div className="w-full max-w-xs">
              <FlashMessages errors={errors} />

              <form onSubmit={submit} className="space-y-4 mt-4">
                <FieldGroup>
                  <div className="flex flex-col items-center gap-1 text-center">
                    <h1 className="text-2xl font-bold">Create an account</h1>
                    <p className="text-muted-foreground text-sm text-balance">
                      Enter your details below to create your account
                    </p>
                  </div>

                  {/* Name Fields */}
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
                        autoComplete="email"
                        aria-invalid={!!errors['user.email']}
                      />
                    </FieldContent>
                    {errors['user.email'] && <FieldError>{errors['user.email']}</FieldError>}
                  </Field>

                  {/* Password Field */}
                  <Field>
                    <FieldLabel>
                      <Label htmlFor="password">Password</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        id="password"
                        type="password"
                        value={data.user.password}
                        onChange={(e) => setData('user', { ...data.user, password: e.target.value })}
                        required
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
                    {processing ? 'Creating account...' : 'Sign up'}
                  </Button>

                  {/* Login link */}
                  <div className="text-center text-sm">
                    <span className="text-muted-foreground">Already have an account? </span>
                    <Link
                      href="/login"
                      className="text-foreground hover:text-primary transition-colors underline-offset-4 hover:underline font-medium"
                    >
                      Log in
                    </Link>
                  </div>
                </FieldGroup>
              </form>
            </div>
          </div>
        </div>
        <div className="bg-muted relative hidden lg:block">
          <img
            src="/placeholder.svg"
            alt="Image"
            className="absolute inset-0 h-full w-full object-cover dark:brightness-[0.2] dark:grayscale"
          />
        </div>
      </div>
    </>
  )
}
