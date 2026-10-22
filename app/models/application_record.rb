class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # `audited` opts a model into the activity log.
  include Auditable

  # Rails binds integer columns as 4-byte values and raises ActiveModel::RangeError
  # (a 500) on anything larger, so integer inputs are capped by validation instead.
  MAX_INTEGER = 2**31 - 1

  # A whole http(s) URL. make_regexp alone also matches a URL buried in other
  # text, so "javascript:alert(1)//http://x.com" would pass: anchor it.
  HTTP_URL_FORMAT = /\A#{URI::DEFAULT_PARSER.make_regexp(%w[http https])}\z/
end
