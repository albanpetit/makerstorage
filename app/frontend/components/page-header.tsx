import { ReactNode } from 'react'

import { ReadOnlyBadge } from '@/components/read-only-badge'
import { SidebarTrigger } from '@/components/ui/sidebar'

interface PageHeaderProps {
  title: string
  subtitle?: string
  children?: ReactNode
}

export function PageHeader({ title, subtitle, children }: PageHeaderProps) {
  return (
    <header className="flex shrink-0 flex-wrap items-center gap-3 border-b bg-background px-4 py-3 sm:px-5">
      <SidebarTrigger className="-ml-1 md:hidden" />
      <div>
        <h1 className="text-base font-semibold tracking-tight">{title}</h1>
        {subtitle && <p className="text-xs text-muted-foreground">{subtitle}</p>}
      </div>
      <div className="flex-1" />
      <ReadOnlyBadge />
      {children}
    </header>
  )
}
