# frozen_string_literal: true

module Suma
  # Null-object cache used when schema caching is disabled: every fetch misses
  # and nothing is stored, so callers need no conditional guards around a cache.
  class NullCache
    def fetch(*, **) = nil

    def store(*, **) = nil
  end
end
