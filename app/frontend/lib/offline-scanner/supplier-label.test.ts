import { describe, expect, it } from 'vitest'

import { movementReference, parseSupplierLabel } from './supplier-label'

// Same labels as test/services/supplier_label_test.rb: the port must read
// them the same way.
const GS = '\u001D'
const RS = '\u001E'
const EOT = '\u0004'
const ecia = (...fields: string[]) => `[)>${RS}06${GS}${fields.join(GS)}${RS}${EOT}`

describe('parseSupplierLabel', () => {
  it('reads a DigiKey bag label', () => {
    const label = parseSupplierLabel(ecia(
      'P296-1395-5-ND', '1PSN74HC595N', 'K', '1K84512345', '10K98765432', '9D2315',
      '1TABC123', '11K1', '4LMY', 'Q25', '11ZPICK', '12Z4389236', '13Z112233', '20Z000000000000',
    ))

    expect(label).toMatchObject({
      provider: 'digikey', provider_name: 'DigiKey', mpn: 'SN74HC595N', supplier_sku: '296-1395-5-ND',
      customer_part_number: null, quantity: 25, order_number: '84512345', lot: 'ABC123', date_code: '2315',
      country_of_origin: 'MY',
    })
    expect(movementReference(label!)).toBe('DigiKey 84512345')
  })

  it('reads a separator typed as a stand-in by a keyboard-wedge scanner', () => {
    const label = parseSupplierLabel(`[)>{RS}06{GS}PMS-00042{GS}30P296-1395-5-ND{GS}1PSN74HC595N{GS}Q10{RS}{EOT}`)
    expect(label).toMatchObject({ provider: 'digikey', customer_part_number: 'MS-00042', supplier_sku: '296-1395-5-ND', quantity: 10 })
  })

  it('ignores text that is not a bag label', () => {
    expect(parseSupplierLabel('A-3')).toBeNull()
  })
})
