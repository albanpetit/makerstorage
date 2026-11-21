import { describe, expect, it } from 'vitest'

import { escapeHtml, html } from './print-document'

describe('html', () => {
  it('escapes every interpolated value', () => {
    const name = '<img src=x onerror="alert(1)">'
    expect(String(html`<td>${name}</td>`)).toBe('<td>&lt;img src=x onerror=&quot;alert(1)&quot;&gt;</td>')
  })

  it('keeps nested fragments and lists as markup, and drops empty values', () => {
    const rows = ['a&b', '<c>'].map((cell) => html`<li>${cell}</li>`)
    expect(String(html`<ul>${rows}${null}${false}</ul>`)).toBe('<ul><li>a&amp;b</li><li>&lt;c&gt;</li></ul>')
  })
})

describe('escapeHtml', () => {
  it("escapes quotes for attributes", () => {
    expect(escapeHtml(`"it's"`)).toBe('&quot;it&#39;s&quot;')
  })
})
