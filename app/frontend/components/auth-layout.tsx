import { PropsWithChildren } from 'react'
import { usePage } from '@inertiajs/react'

import logo from '/assets/logo.svg'
import authImage from '/assets/auth.jpeg'
import { t } from '@/lib/i18n'

interface AuthLayoutProps {
  eyebrow: string
  headline: string
  description: string
}

export function AuthLayout({ eyebrow, headline, description, children }: PropsWithChildren<AuthLayoutProps>) {
  const { legal } = usePage().props
  const legalLinks = [
    legal?.privacy_policy_url && { href: legal.privacy_policy_url, label: t('Privacy policy') },
    legal?.legal_notice_url && { href: legal.legal_notice_url, label: t('Legal notice') },
  ].filter((link): link is { href: string; label: string } => !!link)

  return (
    <div className="flex min-h-svh w-full bg-background text-foreground">
      <div className="relative hidden flex-1 flex-col justify-between overflow-hidden bg-sidebar p-10 text-white lg:flex">
        <img src={authImage} alt="" className="absolute inset-0 size-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/70 to-black/55" />

        <div className="relative flex items-center gap-2.5">
          <img src={logo} alt={t('Makerstorage')} className="size-9 rounded-md" />
          <span className="text-lg font-semibold tracking-tight">{t('Makerstorage')}</span>
        </div>

        <div className="relative flex flex-1 max-w-md flex-col justify-center">
          <div className="mb-4 font-mono text-xs font-medium tracking-widest text-primary uppercase">
            {eyebrow}
          </div>
          <h1 className="mb-4 text-3xl leading-tight font-semibold tracking-tight text-balance">
            {headline}
          </h1>
          <p className="text-sm leading-relaxed text-white/70">{description}</p>
        </div>
      </div>

      <div className="relative flex flex-1 flex-col justify-center px-6 py-10 md:px-10">
        {/* Mobile backdrop — on desktop the left panel already carries the image */}
        <img src={authImage} alt="" className="absolute inset-0 size-full object-cover lg:hidden" />
        <div className="absolute inset-0 bg-black/50 lg:hidden" />

        <div className="relative mx-auto w-full max-w-sm rounded-2xl border bg-background/90 p-6 shadow-xl backdrop-blur-md lg:rounded-none lg:border-0 lg:bg-transparent lg:p-0 lg:shadow-none lg:backdrop-blur-none">
          {children}
          {legalLinks.length > 0 && (
            <nav aria-label={t('Legal')} className="mt-8 flex justify-center gap-4 text-xs text-muted-foreground">
              {legalLinks.map((link) => (
                <a key={link.href} href={link.href} target="_blank" rel="noreferrer" className="hover:text-foreground hover:underline">
                  {link.label}
                </a>
              ))}
            </nav>
          )}
        </div>
      </div>
    </div>
  )
}
