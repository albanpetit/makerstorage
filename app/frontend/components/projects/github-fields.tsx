import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { t } from '@/lib/i18n'

export interface GithubLinkData {
  repository: string
  ref: string
  path: string
}

interface GithubFieldsProps {
  data: GithubLinkData
  onChange: (data: GithubLinkData) => void
  tokenConfigured: boolean
  autoFocus?: boolean
}

// Repository, branch/tag and folder of a GitHub-linked project. A pasted
// ".../tree/<branch>/<folder>" URL fills the branch and folder on the server
// when those fields are left blank.
export function GithubFields({ data, onChange, tokenConfigured, autoFocus }: GithubFieldsProps) {
  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="github-repository">{t('Repository')}</Label>
        <Input
          id="github-repository"
          value={data.repository}
          onChange={(e) => onChange({ ...data, repository: e.target.value })}
          placeholder={t('owner/name or https://github.com/owner/name')}
          autoFocus={autoFocus}
          required
        />
        <p className="text-xs text-muted-foreground">
          {tokenConfigured
            ? t('Public or private: requests use the GitHub token from Settings → Integrations.')
            : t('A public repository. For a private one, add a GitHub token in Settings → Integrations first.')}
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="github-ref">{t('Branch, tag or commit')}</Label>
          <Input
            id="github-ref"
            value={data.ref}
            onChange={(e) => onChange({ ...data, ref: e.target.value })}
            placeholder={t('Default branch')}
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="github-path">{t('Folder')}</Label>
          <Input
            id="github-path"
            value={data.path}
            onChange={(e) => onChange({ ...data, path: e.target.value })}
            placeholder={t('Repository root')}
          />
        </div>
      </div>
    </div>
  )
}
