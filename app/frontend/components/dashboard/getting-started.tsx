import { Link, router } from '@inertiajs/react'
import { useState } from 'react'
import { CheckCircle2, Circle, GraduationCap, Home, PlayCircle, Users, X, type LucideIcon } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { t } from '@/lib/i18n'

export type OnboardingStepKey = 'categories' | 'zones' | 'supplier' | 'part' | 'stock' | 'project' | 'members'

export interface GettingStarted {
  choose_template: boolean
  template: string | null
  steps: { key: OnboardingStepKey; done: boolean }[]
}

const STEP_META: Record<OnboardingStepKey, { label: string; hint: string; href: string }> = {
  categories: {
    get label() { return t('Set up your categories') },
    get hint() { return t('Resistors, capacitors, modules… with their parameters.') },
    href: '/categories',
  },
  zones: {
    get label() { return t('Create your storage zones') },
    get hint() { return t('Rooms, cabinets, drawers and boxes.') },
    href: '/storage_locations',
  },
  supplier: {
    get label() { return t('Add your suppliers') },
    get hint() { return t('Or connect Mouser, DigiKey or LCSC in Settings.') },
    href: '/suppliers',
  },
  part: {
    get label() { return t('Add your first part') },
    get hint() { return t('By hand, from a supplier lookup or a CSV import.') },
    href: '/parts?new=1',
  },
  stock: {
    get label() { return t('Put stock on a shelf') },
    get hint() { return t('Record a stock entry or receive an order.') },
    href: '/parts',
  },
  project: {
    get label() { return t('Create a project') },
    get hint() { return t('Import a BOM to see what you can build.') },
    href: '/projects',
  },
  members: {
    get label() { return t('Invite your members') },
    get hint() { return t('They join once they accept the invitation.') },
    href: '/members',
  },
}

const TEMPLATES: { key: string; icon: LucideIcon; label: string; description: string }[] = [
  {
    key: 'makerspace',
    icon: Users,
    get label() { return t('Makerspace or fablab') },
    get description() { return t('Full electronics categories, a component cabinet with drawers, boxes, a soldering bench and a tool shelf.') },
  },
  {
    key: 'home_lab',
    icon: Home,
    get label() { return t('Home workshop') },
    get description() { return t('The usual categories without the extras, a workbench and a 12-drawer organizer.') },
  },
  {
    key: 'classroom',
    icon: GraduationCap,
    get label() { return t('Classroom or school lab') },
    get description() { return t('Modules, sensors and breadboards, student kit bins and a lending shelf. Loans last a week.') },
  },
]

function TemplateChooser() {
  const [busy, setBusy] = useState<string | null>(null)

  const post = (url: string, data: Record<string, string> = {}, key = url) => {
    setBusy(key)
    router.post(url, data, { onFinish: () => setBusy(null) })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('Start from a template')}</CardTitle>
        <CardDescription>
          {t('Pick what looks like your place: categories with their parameters, footprints and a storage tree are created for you. Everything can be renamed or deleted afterwards.')}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-3 md:grid-cols-3">
          {TEMPLATES.map((template) => (
            <Button
              key={template.key}
              type="button"
              variant="outline"
              disabled={busy !== null}
              onClick={() => post('/onboarding/template', { template: template.key }, template.key)}
              className="h-auto flex-col items-start gap-2 whitespace-normal p-4 text-left"
            >
              <span className="flex items-center gap-2 font-semibold">
                <template.icon className="size-4" />
                {template.label}
              </span>
              <span className="text-xs font-normal text-muted-foreground">{template.description}</span>
            </Button>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" variant="secondary" size="sm" disabled={busy !== null} onClick={() => post('/onboarding/demo')}>
            <PlayCircle className="size-4" />
            {t('Explore a demo first')}
          </Button>
          <Button type="button" variant="ghost" size="sm" disabled={busy !== null} onClick={() => post('/onboarding/skip')}>
            {t('Start empty')}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

export function GettingStartedCard({
  gettingStarted,
  canWrite,
  canAdminister,
}: {
  gettingStarted: GettingStarted
  canWrite: boolean
  canAdminister: boolean
}) {
  if (gettingStarted.choose_template && canAdminister) return <TemplateChooser />

  const items = gettingStarted.steps.map((step) => ({ ...step, ...STEP_META[step.key] }))
  const doneCount = items.filter((item) => item.done).length

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-2">
        <div className="space-y-1.5">
          <CardTitle>{t('First steps')}</CardTitle>
          <CardDescription>
            {t('{done} of {total} done. Each step ticks itself as you go.', { done: doneCount, total: items.length })}
          </CardDescription>
        </div>
        {canAdminister && (
          <Button
            type="button"
            variant="ghost"
            size="icon-sm"
            title={t('Hide the first steps')}
            aria-label={t('Hide the first steps')}
            onClick={() => router.post('/onboarding/dismiss')}
          >
            <X className="size-4" />
          </Button>
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        <ol className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((item) => {
            const content = (
              <>
                {item.done ? (
                  <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-emerald-600" />
                ) : (
                  <Circle className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
                )}
                <div>
                  <p className={`text-sm font-medium ${item.done ? 'text-muted-foreground line-through' : ''}`}>{item.label}</p>
                  <p className="text-xs text-muted-foreground">{item.hint}</p>
                </div>
              </>
            )
            return (
              <li key={item.key}>
                {canWrite && !item.done ? (
                  <Link href={item.href} className="flex gap-3 rounded-lg border p-3 hover:bg-muted/50">
                    {content}
                  </Link>
                ) : (
                  <div className="flex gap-3 rounded-lg border p-3">{content}</div>
                )}
              </li>
            )
          })}
        </ol>
        <Button type="button" variant="link" size="sm" className="h-auto p-0" onClick={() => router.post('/onboarding/demo')}>
          <PlayCircle className="size-4" />
          {t('Explore a demo organization')}
        </Button>
      </CardContent>
    </Card>
  )
}
