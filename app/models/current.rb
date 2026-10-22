# Per-request state. `user` is whoever is signed in (set by
# ApplicationController): changes made with it set are written to the
# activity log (Auditable); jobs, signups and console sessions leave it nil.
class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :activity_suppressed
end
