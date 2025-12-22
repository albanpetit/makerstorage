import { usePage } from '@inertiajs/react'
import { CircleAlert, CircleCheck } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import type { Flash } from '@/types'

interface FlashMessagesProps {
  errors?: Record<string, string | string[]>
}

export function FlashMessages({ errors }: FlashMessagesProps = {}) {
  const { flash } = usePage<{ flash: Flash }>().props

  // Collect error messages to display
  const errorMessages: string[] = []

  // Add flash alert
  if (flash?.alert) {
    errorMessages.push(flash.alert)
  }

  // Add form errors (filter out field-specific nested errors like 'user.email')
  if (errors) {
    Object.entries(errors).forEach(([key, message]) => {
      // Show base/general errors or non-nested field errors
      if (key === 'base' || !key.includes('.')) {
        if (Array.isArray(message)) {
          errorMessages.push(...message)
        } else {
          errorMessages.push(message)
        }
      }
    })
  }

  const hasErrors = errorMessages.length > 0
  const hasNotice = flash?.notice

  if (!hasErrors && !hasNotice) {
    return null
  }

  return (
    <div className="space-y-2">
      {hasErrors && (
        <Alert variant="destructive">
          <CircleAlert />
          <AlertDescription>
            {errorMessages.length === 1 ? (
              errorMessages[0]
            ) : (
              <ul className="list-disc list-inside space-y-1">
                {errorMessages.map((msg, i) => (
                  <li key={i}>{msg}</li>
                ))}
              </ul>
            )}
          </AlertDescription>
        </Alert>
      )}
      {hasNotice && (
        <Alert variant="success">
          <CircleCheck />
          <AlertDescription>{flash.notice}</AlertDescription>
        </Alert>
      )}
    </div>
  )
}
