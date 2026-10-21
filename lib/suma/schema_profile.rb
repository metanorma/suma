# frozen_string_literal: true

module Suma
  # Declares how a schema collection maps schema identifiers and paths
  # to schema types, and how identifiers become display names.
  #
  # Suma works with any schema collection: ISO 10303 conventions (the
  # `_arm`/`_mim` suffixes, the `resources/`+`modules/` directory tree,
  # the ARM/MIM display labels) are one profile among many, not
  # hardcoded behavior. A new collection's conventions are a new profile
  # declaration — no changes to classification, naming, categories, or
  # term extraction.
  #
  # Rules are ordered: the first matching rule classifies the schema.
  # In the ISO 10303 profile the `/applications/` path rule precedes the
  # suffix rules so an AP publication's `_arm`/`_mim` schemas classify as
  # application protocols, while the same suffixes under `modules/`
  # classify as before.
  #
  # @example
  #   SchemaProfile.fetch("iso10303").classify(
  #     id: "ap242_foo_mim", path: "applications/ap242/foo.exp"
  #   ) # => :application_protocol
  #   SchemaProfile.fetch("generic").classify(id: "x", path: "y.exp")
  #   # => :standalone
  class SchemaProfile
    # A single classification rule: +kind+ is :suffix (matched against the
    # lowercased schema identifier) or :path (matched against the schema
    # file path); +pattern+ is the string to match; +type+ is the
    # ExpressSchema::Type symbol the rule produces.
    Rule = Struct.new(:kind, :pattern, :type) do
      def match(schema_id, schema_path)
        case kind
        when :suffix
          schema_id&.downcase&.end_with?(pattern)
        when :path
          schema_path.to_s.include?(pattern)
        end
      end
    end

    attr_reader :id, :rules, :suffix_labels, :acronyms,
                :acronym_patterns, :category_ids

    # (a data-declaring initializer; six keywords by design)
    def initialize(id:, rules: [], suffix_labels: {}, acronyms: [], # rubocop:disable Metrics/ParameterLists
                   acronym_patterns: [], category_ids: %w[other])
      @id = id
      @rules = rules.freeze
      @suffix_labels = suffix_labels.freeze
      @acronyms = acronyms.freeze
      @acronym_patterns = acronym_patterns.freeze
      @category_ids = category_ids.freeze
      freeze
    end

    # Classify a schema under this profile.
    #
    # @param id [String, nil] schema identifier
    # @param path [String, Pathname, nil] schema file path
    # @return [Symbol] an ExpressSchema::Type value; +:standalone+ when no
    #   rule matches
    def classify(id:, path:)
      rules.each do |rule|
        return rule.type if rule.match(id, path)
      end
      ExpressSchema::Type::STANDALONE
    end

    # The default (ISO 10303) profile.
    #
    # @return [SchemaProfile]
    def self.default
      fetch("iso10303")
    end

    # Look up a registered profile by id; +nil+ yields the default.
    #
    # @param id [String, Symbol, SchemaProfile, nil]
    # @return [SchemaProfile]
    # @raise [Suma::Error] on an unknown profile id
    def self.fetch(id)
      return id if id.is_a?(SchemaProfile)
      return default if id.nil?

      REGISTRY.fetch(id.to_s) do
        raise Error, "[suma] unknown schema profile #{id.inspect} " \
                     "(registered: #{REGISTRY.keys.sort.join(', ')})"
      end
    end

    ISO_10303 = new(
      id: "iso10303",
      rules: [
        Rule.new(:path, "/applications/", :application_protocol),
        Rule.new(:suffix, "_arm", :module_arm),
        Rule.new(:suffix, "_mim", :module_mim),
        Rule.new(:suffix, "_bom", :business_object_model),
        Rule.new(:path, "/resources/", :resource),
        Rule.new(:path, "/modules/", :module_arm),
        Rule.new(:path, "/core_model/", :core_model),
      ],
      suffix_labels: {
        "_arm" => "ARM",
        "_mim" => "MIM",
        "_bom" => "BOM",
        "_schema" => nil,
      },
      acronyms: %w[
        aic aec ap apu bom csg edraw id ifc pdf pld
        xml xpdl 2d 3d
      ],
      # AP publications glue the number to the prefix: ap203, ap242, ...
      acronym_patterns: [/\Aap\d+\z/],
      category_ids: %w[
        resources application_protocols modules
        business_object_models core_model other
      ],
    )

    GENERIC = new(
      id: "generic",
      rules: [],
      suffix_labels: {},
      acronyms: [],
      category_ids: %w[other],
    )

    # buildingSMART IFC: one standalone schema per edition (IFC4, IFC4X3,
    # ...), entities prefixed Ifc, no ARM/MIM-style decomposition.
    IFC = new(
      id: "ifc",
      rules: [],
      suffix_labels: {},
      acronyms: %w[bim ifc idf 2d 3d 4d 5d],
      acronym_patterns: [/\Aifc\d+(x\d+)*\z/],
      category_ids: %w[other],
    )

    REGISTRY = {
      "iso10303" => ISO_10303,
      "generic" => GENERIC,
      "ifc" => IFC,
    }.freeze
  end
end
