# One build of a project: +quantity+ kits deducted from stock at +built_at+.
# The "out" movements the build wrote reference it, so the history can show
# what each build consumed; they outlive it (the ledger is never deleted).
class ProjectBuild < ApplicationRecord
  # Associations
  belongs_to :project
  belongs_to :user, optional: true
  has_many :stock_movements, dependent: :nullify

  # Validations
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_INTEGER }
  validates :built_at, presence: true
  validates :note, length: { maximum: 255 }

  # Scopes
  scope :recent, -> { order(built_at: :desc, id: :desc) }
end
