# frozen_string_literal: true

require "yaml"

module Suma
  module Delivery
    # Per-page inventory ratchet (TRThurman, iso-10303#857): the
    # verifier's machine-readable page inventory (image and link counts
    # per page) compared against a committed baseline, so silent
    # rendering drift — a lost figure, a dropped navigation link —
    # fails `delivery verify --inventory-baseline`. The baseline format
    # is deliberately flat YAML, page path => { imgs:, links: }:
    # free-form page keys, so it is plain data, not a fixed-shape
    # lutaml-model document.
    class PageInventory
      # The counted quantities, in report-key order.
      COUNT_KEYS = %w[imgs links].freeze

      class << self
        # The baseline census read from YAML: page path => count hash.
        def load_baseline(yaml)
          data = YAML.safe_load(yaml)
          raise ArgumentError, "baseline must be a YAML mapping" unless
            data.is_a?(Hash)

          data.transform_values do |counts|
            (counts || {}).transform_values(&:to_i)
          end
        end

        # Pages whose counts differ between the current inventory and
        # the baseline: page path => { key => [baseline, current] }.
        # Pages present on only one side count the missing side as zero.
        def changes(current, baseline)
          (current.keys | baseline.keys).filter_map do |page|
            delta = count_changes(page, current, baseline)
            next if delta.empty?

            [page, delta]
          end.to_h
        end

        # Human-readable drift lines: "page (imgs 2->1, links 5->4)".
        def format_changes(changes)
          changes.map do |page, delta|
            moved = delta.map { |key, pair| "#{key} #{pair[0]}->#{pair[1]}" }
            "#{page} (#{moved.join(', ')})"
          end.join("; ")
        end

        private

        # The moved counts of one page.
        def count_changes(page, current, baseline)
          COUNT_KEYS.filter_map do |key|
            old = baseline.fetch(page, {})[key].to_i
            now = current.fetch(page, {})[key].to_i
            next if old == now

            [key, [old, now]]
          end.to_h
        end
      end
    end
  end
end
