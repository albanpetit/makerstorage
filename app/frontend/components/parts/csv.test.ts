import { describe, expect, it } from 'vitest'

import { csvEscape, parseCsvPreview } from './csv'

describe('csvEscape', () => {
  it.each(['=HYPERLINK("http://evil")', '+1+1', '-cmd', '@SUM(A1)', '\tx'])('neutralizes the formula %j', (value) => {
    expect(csvEscape(value).replace(/^"|"$/g, '')).toMatch(/^'/)
  })

  it('leaves plain and negative numbers alone', () => {
    expect(csvEscape('-12.5')).toBe('-12.5')
    expect(csvEscape('42')).toBe('42')
  })

  it('quotes separators, quotes and line breaks', () => {
    expect(csvEscape('a,b')).toBe('"a,b"')
    expect(csvEscape('say "hi"')).toBe('"say ""hi"""')
    expect(csvEscape('two\nlines')).toBe('"two\nlines"')
  })
})

describe('parseCsvPreview', () => {
  it('reads French headers, semicolons, quotes and a BOM', () => {
    const result = parseCsvPreview('﻿Désignation;Catégorie;MPN\r\n"Résistance; 10k";Résistances;RC-10K\r\n')
    expect(result).toEqual({ rows: [{ name: 'Résistance; 10k', category: 'Résistances', mpn: 'RC-10K', sku: '' }] })
  })

  it('skips rows without a name or category', () => {
    const result = parseCsvPreview('Name,Category\nA,B\n,C\nD,\n')
    expect(result).toEqual({ rows: [{ name: 'A', category: 'B', mpn: '', sku: '' }] })
  })

  it('explains a file it cannot use', () => {
    expect(parseCsvPreview('Name,Category\n')).toHaveProperty('error')
    expect(parseCsvPreview('Foo,Bar\n1,2\n')).toHaveProperty('error')
  })
})
