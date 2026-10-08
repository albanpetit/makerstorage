class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Rails binds integer columns as 4-byte values and raises ActiveModel::RangeError
  # (a 500) on anything larger, so integer inputs are capped by validation instead.
  MAX_INTEGER = 2**31 - 1
end
