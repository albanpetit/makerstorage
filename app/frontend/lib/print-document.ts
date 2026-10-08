// Printable documents (part labels, purchase orders) are written into a blank
// window that shares the app's origin, so any markup in them runs with the
// user's session. Build them with the `html` tag below: every interpolated
// value is HTML-escaped unless it is itself an `html` fragment, so user data
// (part names, references, zone names) can never inject markup or scripts.

class SafeHtml {
  constructor(readonly value: string) {}

  toString() {
    return this.value
  }
}

const ESCAPES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
}

export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => ESCAPES[char])
}

function render(value: unknown): string {
  if (value instanceof SafeHtml) return value.value
  if (Array.isArray(value)) return value.map(render).join('')
  if (value == null || value === false) return ''
  return escapeHtml(String(value))
}

export function html(strings: TemplateStringsArray, ...values: unknown[]): SafeHtml {
  let out = strings[0]
  values.forEach((value, i) => {
    out += render(value) + strings[i + 1]
  })
  return new SafeHtml(out)
}

// Opens a new window holding +body+ and triggers the browser's print dialog.
export function printDocument(title: string, body: SafeHtml, bodyStyle = '') {
  const doc = html`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${title}</title></head>
    <body style="${bodyStyle}">${body}</body></html>`

  const printWindow = window.open('', '_blank')
  if (!printWindow) return

  printWindow.document.write(doc.value)
  printWindow.document.close()
  printWindow.focus()
  setTimeout(() => printWindow.print(), 300)
}
