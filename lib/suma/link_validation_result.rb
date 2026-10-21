# frozen_string_literal: true

module Suma
  # One unresolved link reported by a validator: where it was found, what
  # it pointed at, and why it does not resolve.
  LinkValidationResult = Struct.new(:file, :line, :link, :reason,
                                    keyword_init: true)
end
