import { Head, useForm } from '@inertiajs/react'
import { FormEventHandler } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Field, FieldContent, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { Checkbox } from "@/components/ui/checkbox"

interface LoginProps {
  flash?: {
    alert?: string
    notice?: string
  }
}

export default function Login({ flash }: LoginProps) {
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
      <Head title="Log in" />

      <div className="grid min-h-svh lg:grid-cols-2 bg-background text-foreground">
        <div className="flex flex-col gap-4 p-6 md:p-10 bg-background text-foreground">
          <div className="flex flex-1 items-center justify-center">
            <div className="w-full max-w-xs">
              {/* Flash messages */}
              {flash?.alert && (
                <div className="mb-4 p-3 bg-destructive/10 text-destructive rounded-md text-sm">
                  {flash.alert}
                </div>
              )}
              {flash?.notice && (
                <div className="mb-4 p-3 bg-primary/10 text-primary rounded-md text-sm">
                  {flash.notice}
                </div>
              )}

              <form onSubmit={submit} className="space-y-4">
                <FieldGroup>
                  <div className="flex flex-col items-center gap-1 text-center">
                    <h1 className="text-2xl font-bold">Login to your account</h1>
                    <p className="text-muted-foreground text-sm text-balance">
                      Enter your email below to login to your account
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
                        aria-invalid={!!errors.email}
                      />
                    </FieldContent>
                    {errors.email && <FieldError>{errors.email}</FieldError>}
                  </Field>

                  {/* Password Field */}
                  <Field>
                    <div className='flex items-center'>
                      <FieldLabel className='flex'>
                          <Label htmlFor="password">Password</Label>
                      </FieldLabel>
                      <a
                        href="#"
                        className="text-sm ml-auto text-muted-foreground hover:text-foreground transition-colors underline-offset-4 hover:underline"
                      >
                        Forgot password?
                      </a>
                    </div>
                    <FieldContent>
                      <Input
                        id="password"
                        type="password"
                        value={data.user.password}
                        onChange={(e) => setData('user', { ...data.user, password: e.target.value })}
                        required
                        autoComplete="current-password"
                        aria-invalid={!!errors.password}
                      />
                    </FieldContent>
                    {errors.password && <FieldError>{errors.password}</FieldError>}
                  </Field>

                  {/* Remember Me Checkbox */}
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id="remember_me"
                      checked={data.remember_me}
                      onCheckedChange={(checked) => setData('remember_me', checked === true)}
                    />
                    <Label htmlFor="remember_me" className="text-sm font-normal cursor-pointer">
                      Remember me
                    </Label>
                  </div>

                  {/* Submit Button */}
                  <Button
                    type="submit"
                    className="w-full"
                    disabled={processing}
                  >
                    {processing ? 'Logging in...' : 'Log in'}
                  </Button>

                  {/* Sign up link */}
                  <div className="text-center text-sm">
                    <span className="text-muted-foreground">Don't have an account? </span>
                    <a
                      href="#"
                      className="text-foreground hover:text-primary transition-colors underline-offset-4 hover:underline font-medium"
                    >
                      Sign up
                    </a>
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
