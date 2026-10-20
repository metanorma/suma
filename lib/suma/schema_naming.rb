# frozen_string_literal: true

module Suma
  # Converts EXPRESS schema identifiers into human-readable display names.
  #
  # Naming is profile-driven: the profile declares the suffixes
  # stripped from the identifier (with their parenthesised labels) and
  # the acronyms preserved during title-casing. The ISO 10303 profile
  # reproduces the historical behavior — ARM/MIM/BOM labels and the ISO
  # acronym set; the generic profile strips nothing and applies plain
  # title-casing.
  #
  # @example
  #   SchemaNaming.display_name("topology_schema")
  #   # => "Topology"
  #   SchemaNaming.display_name("Activity_method_assignment_mim")
  #   # => "Activity Method Assignment (MIM)"
  #   SchemaNaming.display_name("aic_advanced_brep")
  #   # => "AIC Advanced Brep"
  module SchemaNaming
    # Lowercase function words (ISO title-case convention).
    LOWERCASE_WORDS = %w[a an and as for in of on or the to].freeze

    class << self
      # Produce a human-readable display name from a schema identifier.
      #
      # @param schema_id [String] the EXPRESS schema identifier
      # @param profile [SchemaProfile, Symbol, String, nil] schema profile
      # @return [String] human-readable name
      def display_name(schema_id, profile: nil)
        profile_obj = SchemaProfile.fetch(profile)
        base, label = decompose(schema_id, profile_obj.suffix_labels)
        title_cased = title_case(base, profile_obj)
        label ? "#{title_cased} (#{label})" : title_cased
      end

      # Produce a prefixed display name with the schema category.
      #
      # @param schema_id [String] the EXPRESS schema identifier
      # @param path [String, Pathname] the schema file path (for classification)
      # @param profile [SchemaProfile, Symbol, String, nil] schema profile
      # @return [String] e.g. "Resource: Topology" or "Module: Activity (ARM)"
      def prefixed_name(schema_id, path: nil, profile: nil)
        type = ExpressSchema::Type.classify(id: schema_id, path: path,
                                            profile: profile)
        prefix = category_prefix(type)
        "#{prefix}: #{display_name(schema_id, profile: profile)}"
      end

      # Determine the category prefix for a schema type.
      #
      # @param type [Symbol] one of ExpressSchema::Type constants
      # @return [String]
      def category_prefix(type)
        SchemaCategory.for_type(type).prefix
      end

      private

      # Split a schema ID into (base_without_suffix, suffix_label_or_nil).
      #
      # @param schema_id [String]
      # @param suffix_labels [Hash{String => String, nil}]
      # @return [(String, String, nil)]
      def decompose(schema_id, suffix_labels)
        suffix_labels.each do |suffix, label|
          if schema_id.end_with?(suffix)
            return [schema_id.delete_suffix(suffix),
                    label]
          end
        end
        [schema_id, nil]
      end

      # Title-case a snake_case identifier, preserving acronyms.
      # The +tr+ collapses runs of underscores (leading, trailing, and
      # consecutive) into spaces, which +split+ then treats as a single
      # separator.
      #
      # @param name [String] snake_case identifier
      # @param acronyms [Array<String>] lowercased words kept uppercase
      # @return [String] title-cased name
      def title_case(name, profile_obj)
        words = name.tr("_", " ").split
        words.each_with_index.map do |word, i|
          capitalize_word(word, profile_obj: profile_obj, first: i.zero?)
        end.join(" ")
      end

      # Capitalise a single word, preserving acronyms and
      # lowercasing function words (except when first in the name).
      #
      # @param word [String]
      # @param acronyms [Array<String>]
      # @param first [Boolean] whether this is the first word
      # @return [String]
      def capitalize_word(word, profile_obj:, first: false)
        lower = word.downcase
        return word.upcase if profile_obj.acronyms.include?(lower)
        return word.upcase if profile_obj.acronym_patterns.any? { |re| re.match?(lower) }
        return word.downcase if LOWERCASE_WORDS.include?(lower) && !first

        word.capitalize
      end
    end
  end
end
