class OrderLine < ApplicationRecord
  # Associations
  belongs_to :order
  belongs_to :part

  # Validations
  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Methods
  def subtotal
    return nil if unit_price.nil?
    quantity * unit_price
  end
end
