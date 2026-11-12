# frozen_string_literal: true

module Suma
  module Delivery
    # Corpus-side gate thresholds for `delivery verify --expectations`:
    # the measured site-shape conditions as data, so the calling workflow
    # states its delivery contract in one manifest instead of hand-rolled
    # shell checks. Unset attributes are not checked.
    class Expectations < Lutaml::Model::Serializable
      attribute :sections_min, :integer
      attribute :index_pages, :integer
      attribute :schema_attachments_min, :integer
      attribute :schema_docs_min, :integer
      attribute :missing_express_max, :integer, default: -> { 0 }
      attribute :broken_links_max, :integer, default: -> { 0 }

      key_value do
        map "sections_min", to: :sections_min
        map "index_pages", to: :index_pages
        map "schema_attachments_min", to: :schema_attachments_min
        map "schema_docs_min", to: :schema_docs_min
        map "missing_express_max", to: :missing_express_max
        map "broken_links_max", to: :broken_links_max
      end

      # Human-readable violation lines for every threshold the +inventory+
      # and +broken_links+ breach; unset thresholds stay silent. The name
      # suffix is the comparison: `_min` floors, `_max` caps, a bare name
      # (index_pages) is exact.
      def violations(inventory, broken_links)
        actuals(inventory, broken_links).filter_map do |name, actual|
          limit = public_send(name) or next
          relation = relation_of(name)
          met = case relation
                when "at least" then actual >= limit
                when "at most" then actual <= limit
                else actual == limit
                end
          next if met

          format("%<name>s: got %<actual>d, expected %<relation>s " \
                 "%<limit>d", name: name, actual: actual,
                              relation: relation, limit: limit)
        end
      end

      private

      def relation_of(name)
        return "at least" if name.end_with?("_min")
        return "at most" if name.end_with?("_max")

        "exactly"
      end

      # Every threshold's observed value, keyed by threshold name.
      def actuals(inventory, broken_links)
        {
          "sections_min" => inventory["sections"],
          "index_pages" => inventory["index_pages"],
          "schema_attachments_min" => inventory["schema_attachments"],
          "schema_docs_min" => inventory["schema_docs"],
          "missing_express_max" => inventory["missing_express_pages"].size,
          "broken_links_max" => broken_links.size,
        }
      end
    end
  end
end
