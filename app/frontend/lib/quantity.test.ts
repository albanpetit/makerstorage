import { afterEach, describe, expect, it } from 'vitest'

import { setLocale } from './i18n'
import { cleanQuantityInput, formatQuantity, parseQuantity, sumQuantities } from './quantity'

describe('parseQuantity', () => {
  // Must stay in step with Quantity.parse (app/models/quantity.rb).
  it.each([
    ['12', 12],
    ['2.5', 2.5],
    ['2,5', 2.5],
    [' 0.125 ', 0.125],
    ['.5', 0.5],
    ['-3', -3],
    ['1.23456', 1.235],
  ])('reads %j as %d', (text, expected) => {
    expect(parseQuantity(text)).toBe(expected)
  })

  it.each(['', 'abc', '1.2.3', '~50', 'n/a', '1e3', '2,5,1'])('refuses %j', (text) => {
    expect(parseQuantity(text)).toBeNull()
  })
})

describe('cleanQuantityInput', () => {
  it('keeps digits only for a count unit', () => {
    expect(cleanQuantityInput('1.5 pcs', 'piece')).toBe('15')
  })

  it('keeps one separator and three decimals for a measure', () => {
    expect(cleanQuantityInput('2,5.7891', 'meter')).toBe('2,578')
  })
})

describe('formatQuantity', () => {
  afterEach(() => setLocale('en'))

  it('follows the UI language and adds the unit symbol', () => {
    expect(formatQuantity(2.5, 'meter')).toBe('2.5 m')
    setLocale('fr')
    expect(formatQuantity(0.5, 'liter')).toBe('0,5 L')
  })
})

describe('sumQuantities', () => {
  it('adds without float noise', () => {
    expect(sumQuantities([0.1, 0.2])).toBe(0.3)
  })
})
