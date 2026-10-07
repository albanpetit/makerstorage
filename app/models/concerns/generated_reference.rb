# Saving a record under a reference drawn from a "first free one" lookup
# (Order.next_reference, Project.next_reference). The lookup can't see a
# reference another request is about to insert, so two concurrent creations
# can draw the same one; the per-organization unique index (or the uniqueness
# validation, if the other request already committed) then rejects the second.
# Rather than surfacing that as an error, draw the next free reference and try
# again.
module GeneratedReference
  extend ActiveSupport::Concern

  # Assigns the reference returned by the block and saves (raising like save!),
  # redrawing it up to +attempts+ times when it turns out to be taken.
  def save_with_generated_reference!(attempts: 5)
    attempts.times do |attempt|
      self.reference = yield
      return self.class.transaction(requires_new: true) { save! }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if attempt == attempts - 1
      raise if e.is_a?(ActiveRecord::RecordInvalid) && !reference_taken?
    end
  end

  private

  def reference_taken?
    errors.details[:reference].any? { |detail| detail[:error] == :taken }
  end
end
