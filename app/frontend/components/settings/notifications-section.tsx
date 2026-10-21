import { FormEvent } from 'react'
import { Info, MailWarning } from 'lucide-react'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'

import type { NotificationFrequency, NotificationsForm } from './types'
import { t } from '@/lib/i18n'

// Which alerts the email digest (NotificationDigestJob) sends to members.
export function NotificationsSection({ form, available }: { form: NotificationsForm; available: boolean }) {
  const submit = (e: FormEvent) => {
    e.preventDefault()
    form.patch('/settings', { preserveScroll: true })
  }

  const data = form.data.organization
  const set = (changes: Partial<typeof data>) => form.setData('organization', { ...data, ...changes })

  return (
    <form onSubmit={submit} className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">{t('Notifications')}</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          {t('An email digest of the alerts that need attention, sent to members at 8am in the organization\'s time zone.')}
        </p>
      </div>

      {!available && (
        <Alert>
          <MailWarning />
          <AlertTitle>{t('Email isn\'t set up on this server')}</AlertTitle>
          <AlertDescription>
            {t('No digest is sent until an administrator configures SMTP (SMTP_ADDRESS). Your choices here are kept for then.')}
          </AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader>
          <CardTitle>{t('Email alerts')}</CardTitle>
        </CardHeader>
        <CardContent className="divide-y">
          <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
            <div>
              <div className="text-sm font-medium">{t('Low stock')}</div>
              <div className="text-xs text-muted-foreground">{t('Components below their low-stock threshold.')}</div>
            </div>
            <Switch checked={data.notify_low_stock} onCheckedChange={(checked) => set({ notify_low_stock: checked })} />
          </div>
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">{t('Late orders')}</div>
              <div className="text-xs text-muted-foreground">{t('Open purchase orders past their expected delivery date.')}</div>
            </div>
            <Switch checked={data.notify_late_orders} onCheckedChange={(checked) => set({ notify_late_orders: checked })} />
          </div>
          <div className="flex items-center justify-between gap-4 py-3 last:pb-0">
            <div>
              <div className="text-sm font-medium">{t('Frequency')}</div>
              <div className="text-xs text-muted-foreground">{t('Nothing is sent when there is nothing to report.')}</div>
            </div>
            <Select
              value={data.notification_frequency}
              onValueChange={(value) => set({ notification_frequency: value as NotificationFrequency })}
              disabled={!data.notify_low_stock && !data.notify_late_orders}
            >
              <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="daily">{t('Daily')}</SelectItem>
                <SelectItem value="weekly">{t('Weekly (Mondays)')}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardContent>
        <CardFooter className="justify-end border-t">
          <Button type="submit" disabled={form.processing}>{t('Save')}</Button>
        </CardFooter>
      </Card>
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <Info className="size-3.5 shrink-0" />
        {t('Each member can also turn the digest off for themselves from their profile.')}
      </div>
    </form>
  )
}
