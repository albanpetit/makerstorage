import { FormEvent } from 'react'
import { Info, MailWarning } from 'lucide-react'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'

import type { NotificationFrequency, NotificationsForm } from './types'

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
        <h2 className="text-lg font-semibold">Notifications</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          An email digest of the alerts that need attention, sent to members at 8am in the organization's time zone.
        </p>
      </div>

      {!available && (
        <Alert>
          <MailWarning />
          <AlertTitle>Email isn't set up on this server</AlertTitle>
          <AlertDescription>
            No digest is sent until an administrator configures SMTP (SMTP_ADDRESS). Your choices here are kept for then.
          </AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Email alerts</CardTitle>
        </CardHeader>
        <CardContent className="divide-y">
          <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
            <div>
              <div className="text-sm font-medium">Low stock</div>
              <div className="text-xs text-muted-foreground">Components below their low-stock threshold.</div>
            </div>
            <Switch checked={data.notify_low_stock} onCheckedChange={(checked) => set({ notify_low_stock: checked })} />
          </div>
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">Late orders</div>
              <div className="text-xs text-muted-foreground">Open purchase orders past their expected delivery date.</div>
            </div>
            <Switch checked={data.notify_late_orders} onCheckedChange={(checked) => set({ notify_late_orders: checked })} />
          </div>
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">Overdue loans</div>
              <div className="text-xs text-muted-foreground">Tools and parts not returned by their due date.</div>
            </div>
            <Switch checked={data.notify_overdue_loans} onCheckedChange={(checked) => set({ notify_overdue_loans: checked })} />
          </div>
          <div className="flex items-center justify-between gap-4 py-3 last:pb-0">
            <div>
              <div className="text-sm font-medium">Frequency</div>
              <div className="text-xs text-muted-foreground">Nothing is sent when there is nothing to report.</div>
            </div>
            <Select
              value={data.notification_frequency}
              onValueChange={(value) => set({ notification_frequency: value as NotificationFrequency })}
              disabled={!data.notify_low_stock && !data.notify_late_orders && !data.notify_overdue_loans}
            >
              <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="daily">Daily</SelectItem>
                <SelectItem value="weekly">Weekly (Mondays)</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardContent>
        <CardFooter className="justify-end border-t">
          <Button type="submit" disabled={form.processing}>Save</Button>
        </CardFooter>
      </Card>
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <Info className="size-3.5 shrink-0" />
        Each member can also turn the digest off for themselves from their profile.
      </div>
    </form>
  )
}
