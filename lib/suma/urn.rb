# frozen_string_literal: true

module Suma
  # Value object encapsulating URN semantics for ISO 10303 datasets.
  #
  # Normalises a URN prefix (stripping any trailing wildcard `:*`) and
  # provides factory methods for composing leaf URNs:
  #
  # - `#for_schema(id)`   → `<base>:tech:<id>`
  # - `#for_term(id)`     → `<base>:term:<id>`
  # - `#for_entity(ref)`  → `<base>:tech:<ref>`
  #
  # The wildcard form is preserved via `#wildcard` and `#aliases` so callers
  # can populate `urnAliases` in register.yaml without re-implementing the
  # normalisation logic.
  class Urn
    WILDCARD_SUFFIX = ":*"
    TECH_COMPONENT = "tech"
    TERM_COMPONENT = "term"

    attr_reader :base

    def initialize(raw)
      @base = strip_wildcard(raw.to_s)
    end

    def to_s
      base
    end

    def wildcard
      "#{base}#{WILDCARD_SUFFIX}"
    end

    def aliases
      [wildcard]
    end

    def for_schema(schema_id)
      compose(TECH_COMPONENT, schema_id)
    end

    def for_term(concept_identifier)
      compose(TERM_COMPONENT, concept_identifier)
    end

    def for_entity(full_ref)
      compose(TECH_COMPONENT, full_ref)
    end

    private

    def strip_wildcard(value)
      value.sub(/#{Regexp.escape(WILDCARD_SUFFIX)}\z/o, "")
    end

    def compose(component, identifier)
      "#{base}:#{component}:#{identifier}"
    end
  end
end
