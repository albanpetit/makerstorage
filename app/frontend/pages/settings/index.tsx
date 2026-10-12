import { Head, useForm } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import { Building2, DatabaseBackup, Hash, Package, ShieldAlert, Plug } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { usePermissions } from '@/hooks/use-permissions'
import { Button } from '@/components/ui/button'
import { BackupSection } from '@/components/settings/backup-section'
import { DangerSection } from '@/components/settings/danger-section'
import { GeneralSection } from '@/components/settings/general-section'
import { IntegrationsSection } from '@/components/settings/integrations-section'
import { InventorySection } from '@/components/settings/inventory-section'
import { IpnSection } from '@/components/settings/ipn-section'
import type {
  GeneralFormData, IntegrationsFormData, InventoryFormData, IpnFormData, SettingsPageProps,
} from '@/components/settings/types'

const SECTIONS = [
  { key: 'general', label: 'General', icon: Building2 },
  { key: 'ipn', label: 'Numbering (IPN)', icon: Hash },
  { key: 'inventory', label: 'Inventory', icon: Package },
  { key: 'integrations', label: 'Integrations', icon: Plug },
  { key: 'backup', label: 'Backup', icon: DatabaseBackup },
  { key: 'danger', label: 'Danger zone', icon: ShieldAlert },
] as const

type SectionKey = (typeof SECTIONS)[number]['key']

export default function SettingsIndex({ organization, currencies, ipn_separators, timezones }: SettingsPageProps) {
  const { isOwner } = usePermissions()
  const [section, setSection] = useState<SectionKey>('general')

  const sections = useMemo(() => SECTIONS.filter((s) => s.key !== 'danger' || isOwner), [isOwner])

  const generalForm = useForm<GeneralFormData>({
    organization: {
      name: organization.name,
      email: organization.email || '',
      phone: organization.phone || '',
      website: organization.website || '',
      logo: null,
      remove_logo: false,
      address_line1: organization.address_line1 || '',
      address_line2: organization.address_line2 || '',
      city: organization.city || '',
      postcode: organization.postcode || '',
      country: organization.country || '',
      currency: organization.currency,
      timezone: organization.timezone,
    },
  })

  const ipnForm = useForm<IpnFormData>({
    organization: {
      ipn_generation_mode: organization.ipn_generation_mode,
      ipn_charset: organization.ipn_charset,
      ipn_prefix: organization.ipn_prefix,
      ipn_separator: organization.ipn_separator,
      ipn_digits: organization.ipn_digits,
      ipn_use_category_code: organization.ipn_use_category_code,
      ipn_next_sequence: organization.ipn_next_sequence,
    },
  })

  const inventoryForm = useForm<InventoryFormData>({
    organization: {
      default_low_stock_threshold: organization.default_low_stock_threshold,
      allow_negative_stock: organization.allow_negative_stock,
      stock_reservations_enabled: organization.stock_reservations_enabled,
    },
  })

  const integrationsForm = useForm<IntegrationsFormData>({
    organization: {
      mouser_api_key: '',
      remove_mouser_api_key: false,
      mouser_order_api_key: '',
      remove_mouser_order_api_key: false,
      digikey_client_id: '',
      digikey_client_secret: '',
      remove_digikey: false,
    },
  })

  // The forms live here rather than in each section so unsaved edits survive
  // switching between sections.
  return (
    <AppLayout header={<PageHeader title="Settings" subtitle="Organization configuration and preferences" />}>
      <Head title="Settings" />

      <div className="space-y-6">
        <FlashMessages />

        <div className="flex flex-col gap-6 lg:flex-row">
          {/* Section nav */}
          <nav className="flex shrink-0 gap-1 overflow-x-auto lg:w-56 lg:flex-col lg:overflow-visible">
            {sections.map((s) => (
              <Button
                key={s.key}
                type="button"
                variant="ghost"
                onClick={() => setSection(s.key)}
                className={`h-auto justify-start gap-2.5 rounded-lg px-3 py-2 text-left has-[>svg]:px-3 ${
                  section === s.key
                    ? 'bg-muted text-foreground hover:bg-muted dark:hover:bg-muted'
                    : s.key === 'danger'
                      ? 'text-destructive hover:bg-destructive/10 hover:text-destructive dark:hover:bg-destructive/10'
                      : 'text-muted-foreground'
                }`}
              >
                <s.icon className="size-4 shrink-0" />
                {s.label}
              </Button>
            ))}
          </nav>

          {/* Content — centered and capped like the mockup's 780px column */}
          <div className="mx-auto w-full min-w-0 max-w-[780px] space-y-4">
            {section === 'general' && (
              <GeneralSection form={generalForm} organization={organization} currencies={currencies} timezones={timezones} />
            )}

            {section === 'ipn' && (
              <IpnSection form={ipnForm} organization={organization} separators={ipn_separators} />
            )}

            {section === 'inventory' && <InventorySection form={inventoryForm} />}

            {section === 'integrations' && <IntegrationsSection form={integrationsForm} organization={organization} />}

            {section === 'backup' && <BackupSection organization={organization} />}

            {section === 'danger' && isOwner && <DangerSection organization={organization} />}
          </div>
        </div>
      </div>
    </AppLayout>
  )
}
