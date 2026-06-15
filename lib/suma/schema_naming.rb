# frozen_string_literal: true

require_relative "express_schema"

module Suma
  # Converts EXPRESS schema identifiers into human-readable display names.
  #
  # Naming is model-driven: the schema type (resource/module) and suffix
  # determine how the identifier is formatted. Acronyms and numeric
  # prefixes are preserved to match ISO 10303 conventions.
  #
  # @example
  #   SchemaNaming.display_name("topology_schema")
  #   # => "Topology"
  #   SchemaNaming.display_name("Activity_method_assignment_mim")
  #   # => "Activity Method Assignment (MIM)"
  #   SchemaNaming.display_name("aic_advanced_brep")
  #   # => "AIC Advanced Brep"
  module SchemaNaming
    # Acronyms preserved as uppercase during title-casing.
    # Source: ISO 10303 naming conventions.
    ACRONYMS = %w[
      aic aec apu bom csg edraw id ifc pdf pld
      xml xpdl 2d 3d
    ].freeze

    # Lowercase function words (ISO title-case convention).
    LOWERCASE_WORDS = %w[a an and as for in of on or the to].freeze

    # Suffixes stripped from the schema name before title-casing,
    # paired with the parenthesised label appended to the display name.
    SUFFIX_LABELS = {
      "_arm" => "ARM",
      "_mim" => "MIM",
      "_bom" => "BOM",
    }.freeze

    # Suffixes stripped with no label appended.
    SUFFIX_SILENT = %w[_schema].freeze

    class << self
      # Produce a human-readable display name from a schema identifier.
      #
      # @param schema_id [String] the EXPRESS schema identifier
      # @return [String] human-readable name
      def display_name(schema_id)
        base, label = decompose(schema_id)
        title_cased = title_case(base)
        label ? "#{title_cased} (#{label})" : title_cased
      end

      # Produce a prefixed display name with the schema category.
      #
      # @param schema_id [String] the EXPRESS schema identifier
      # @param path [String, Pathname] the schema file path (for classification)
      # @return [String] e.g. "Resource: Topology" or "Module: Activity (ARM)"
      def prefixed_name(schema_id, path: nil)
        type = ExpressSchema::Type.classify(id: schema_id, path: path)
        prefix = category_prefix(type)
        "#{prefix}: #{display_name(schema_id)}"
      end

      # Determine the category prefix for a schema type.
      #
      # @param type [Symbol] one of ExpressSchema::Type constants
      # @return [String]
      def category_prefix(type)
        case type
        when :resource then "Resource"
        when :module_arm, :module_mim then "Module"
        when :business_object_model then "Business Object Model"
        when :core_model then "Core Model"
        else "Schema"
        end
      end

      private

      # Split a schema ID into (base_without_suffix, suffix_label_or_nil).
      #
      # @return [Array(String, String, nil)]
      def decompose(schema_id)
        SUFFIX_LABELS.each do |suffix, label|
          if schema_id.end_with?(suffix)
            return [schema_id.sub(/#{suffix}$/, ""), label]
          end
        end

        SUFFIX_SILENT.each do |suffix|
          if schema_id.end_with?(suffix)
            return [schema_id.sub(/#{suffix}$/, ""), nil]
          end
        end

        [schema_id, nil]
      end

      # Title-case a snake_case identifier, preserving acronyms.
      #
      # @param name [String] snake_case identifier
      # @return [String] title-cased name
      def title_case(name)
        words = name.gsub(/_/, " ").split
        words.each_with_index.map do |word, i|
          capitalize_word(word, first: i.zero?)
        end.join(" ")
      end

      # Capitalise a single word, preserving acronyms and
      # lowercasing function words (except when first in the name).
      #
      # @param word [String]
      # @param first [Boolean] whether this is the first word
      # @return [String]
      def capitalize_word(word, first: false)
        return word.upcase if ACRONYMS.include?(word.downcase)
        return word.downcase if LOWERCASE_WORDS.include?(word.downcase) && !first
        word.capitalize
      end
    end
  end
end
