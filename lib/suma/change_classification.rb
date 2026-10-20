# frozen_string_literal: true

module Suma
  # The typed change taxonomy (S3): every schema change is classified as
  # additive, compatible, breaking, or editorial.
  #
  # The mapping is data — a frozen Hash keyed by the eengine action — so a
  # finer-grained rule is a one-line addition. Modifications are classified
  # as breaking conservatively: eengine reports structural deltas (type
  # changes, attribute additions on entities, interface changes) without
  # enough detail to prove backwards compatibility, so additive/editorial
  # claims are only made where the action itself guarantees them.
  class ChangeClassification
    ADDITIVE = "additive"
    COMPATIBLE = "compatible"
    BREAKING = "breaking"
    EDITORIAL = "editorial"

    BY_ACTION = {
      "added" => ADDITIVE,
      "removed" => BREAKING,
      "modified" => BREAKING,
      "mapping" => EDITORIAL,
    }.freeze

    ALL = [ADDITIVE, COMPATIBLE, BREAKING, EDITORIAL].freeze

    # @param action [String, Symbol] added / removed / modified / mapping
    # @return [String] one of ALL
    def self.classify(action:)
      BY_ACTION.fetch(action.to_s) do
        raise Error, "[suma] unknown change action #{action.inspect} " \
                     "(known: #{BY_ACTION.keys.sort.join(', ')})"
      end
    end
  end
end
