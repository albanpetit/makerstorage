import { t } from '@/lib/i18n'

// Mounting types are stored in English (Footprint::MOUNTING_TYPES).
export function mountingTypeLabel(type: string) {
  switch (type) {
    case 'SMD': return t('SMD')
    case 'Through-hole': return t('Through-hole')
    case 'Both': return t('Both')
    default: return type
  }
}
