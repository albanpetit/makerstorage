import { usePage } from '@inertiajs/react'
import { CircleAlert, CircleCheck } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { cn } from '@/lib/utils'
import type { Flash } from '@/types'

interface FlashMessagesProps {
  errors?: Record<string, string | string[]>
  className?: string
}

// Convert field key to human-readable label
function humanizeFieldName(key: string): string {
  // Handle nested keys like 'part.category' -> 'Category'
  const fieldName = key.includes('.') ? key.split('.').pop()! : key

  // Convert snake_case or camelCase to Title Case with spaces
  return fieldName
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

export function FlashMessages({ errors, className }: FlashMessagesProps = {}) {
  const { flash } = usePage<{ flash: Flash }>().props

  // Collect error messages to display
  const errorMessages: string[] = []

  // Add flash alert
  if (flash?.alert) {
    errorMessages.push(flash.alert)
  }

  // Add form errors with field names
  if (errors) {
    Object.entries(errors).forEach(([key, message]) => {
      // Skip nested field errors (like 'user.email') - these are shown inline
      if (key.includes('.')) {
        return
      }

      const fieldLabel = humanizeFieldName(key)
      const messages = Array.isArray(message) ? message : [message]

      messages.forEach((msg) => {
        // For 'base' errors, show message as-is
        // For field errors, prepend the field name
        if (key === 'base') {
          errorMessages.push(msg)
        } else {
          errorMessages.push(`${fieldLabel} ${msg}`)
        }
      })
    })
  }

  const hasErrors = errorMessages.length > 0
  const hasNotice = flash?.notice

  if (!hasErrors && !hasNotice) {
    return null
  }

  return (
    <div className={cn('space-y-2', className)}>
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
