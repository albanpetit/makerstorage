import { PropsWithChildren } from 'react'

import logo from '/assets/logo.svg'

interface AuthLayoutProps {
  eyebrow: string
  headline: string
  description: string
}

export function AuthLayout({ eyebrow, headline, description, children }: PropsWithChildren<AuthLayoutProps>) {
  return (
    <div className="flex min-h-svh w-full bg-background text-foreground">
      <div className="relative hidden flex-1 flex-col justify-between overflow-hidden bg-sidebar p-10 text-sidebar-foreground lg:flex">
        <div
          className="absolute inset-0 opacity-50"
          style={{
            backgroundImage: 'radial-gradient(circle at 1px 1px, var(--sidebar-border) 1px, transparent 0)',
            backgroundSize: '26px 26px',
          }}
        />

        <div className="relative flex items-center gap-2.5">
          <img src={logo} alt="Makerstorage" className="size-9 rounded-md" />
          <span className="text-lg font-semibold tracking-tight">Makerstorage</span>
        </div>

        <div className="relative flex flex-1 max-w-md flex-col justify-center">
          <div className="mb-4 font-mono text-xs font-medium tracking-widest text-primary uppercase">
            {eyebrow}
          </div>
          <h1 className="mb-4 text-3xl leading-tight font-semibold tracking-tight text-balance">
            {headline}
          </h1>
          <p className="text-sm leading-relaxed text-sidebar-foreground/60">{description}</p>
        </div>
      </div>

      <div className="flex flex-1 flex-col justify-center px-6 py-10 md:px-10">
        <div className="mx-auto w-full max-w-sm">{children}</div>
      </div>
    </div>
  )
}
