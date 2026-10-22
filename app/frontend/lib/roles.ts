import { t } from '@/lib/i18n'

// Display name of a membership role (owner, admin, member, viewer).
export function roleLabel(role: string): string {
  switch (role) {
    case 'owner': return t('Owner')
    case 'admin': return t('Admin')
    case 'member': return t('Member')
    case 'viewer': return t('Viewer')
    default: return role
  }
}
