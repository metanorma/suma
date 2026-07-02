# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "utils"
require_relative "express_schema"
require_relative "schema_naming"

module Suma
  # Generates a Glossarist v3 register.yaml from an EXPRESS schema manifest.
  #
  # The schema manifest (schemas-smrl-part-2.yml) is the single source of
  # truth for schema identities and paths. This class reads it, classifies
  # each schema by type (resource/module), and emits a register.yaml with
  # hierarchical sections and human-readable names.
  #
  # Architecture:
  #   - Classification: delegates to ExpressSchema::Type (DRY)
  #   - Naming: delegates to SchemaNaming (OCP — extend naming without
  #     touching this class)
  #   - Section hierarchy: Resource schemas before Module schemas, using
  #     the Section model's +children+ field
  #
  # @example
  #   generator = RegisterGenerator.new(
  #     "schemas-smrl-part-2.yml",
  #     urn: "urn:iso:std:iso:10303:-2:ed-1:en:tech:*",
  #     id: "iso10303-2-express",
  #     ref: "ISO 10303-2 EXPRESS Concepts",
  #   )
  #   generator.generate  # writes register.yaml
  class RegisterGenerator
    # Ordered category definitions. Order determines display order in the
    # generated register (Resources before Modules).
    # Each entry: [type_predicate, group_id, group_label]
    CATEGORY_ORDER = [
      [:resource?, "resources", "Resources"],
      [:module?, "modules", "Application Modules"],
      [:other?, "other", "Other Schemas"],
    ].freeze

    # @param schema_manifest_file [String] path to schemas-smrl-part-2.yml
    # @param output_path [String] directory to write register.yaml
    # @param urn [String] base URN for the dataset
    # @param id [String] dataset identifier
    # @param ref [String] human-readable reference label
    # @param language_code [String] language for section names
    def initialize(schema_manifest_file, output_path, urn:, id:, ref:,
                   language_code: "eng")
      @schema_manifest_file = File.expand_path(schema_manifest_file)
      @output_path = output_path
      @urn = urn
      @id = id
      @ref = ref
      @language_code = language_code
    end

    # Generate and write register.yaml.
    #
    # @return [Hash] the generated register data
    def generate
      schemas = load_schemas
      sections = build_hierarchical_sections(schemas)
      register = build_register(sections)

      FileUtils.mkdir_p(@output_path)
      output_file = File.join(@output_path, "register.yaml")
      File.write(output_file, register.to_yaml)
      Utils.log "Generated register.yaml: #{output_file}"
      Utils.log "  #{schemas.length} schemas in #{sections.length} categories"

      register
    end

    private

    # Load all schemas from the manifest file.
    #
    # @return [Array<Hash>] each entry: {id:, path:, type:}
    def load_schemas
      manifest = YAML.load_file(@schema_manifest_file)
      manifest.fetch("schemas", []).map do |id, info|
        path = info.fetch("path", "")
        {
          id: id,
          path: path,
          type: ExpressSchema::Type.classify(id: id, path: path),
        }
      end.sort_by { |s| s[:id].downcase }
    end

    # Build hierarchical sections grouped by category.
    #
    # @param schemas [Array<Hash>]
    # @return [Array<Hash>] top-level section nodes with children
    def build_hierarchical_sections(schemas)
      groups = categorise(schemas)

      CATEGORY_ORDER.filter_map do |predicate, group_id, group_label|
        children = groups[predicate] || []
        next if children.empty?

        {
          "id" => group_id,
          "names" => { @language_code => group_label },
          "children" => children.map { |s| build_section(s) },
        }
      end
    end

    # Partition schemas into category buckets.
    #
    # @param schemas [Array<Hash>]
    # @return [Hash<Symbol, Array<Hash>>] keyed by predicate symbol
    def categorise(schemas)
      {
        resource?: [],
        module?: [],
        other?: [],
      }.tap do |groups|
        schemas.each do |schema|
          key = category_key(schema[:type])
          groups[key] << schema
        end
      end
    end

    # Map an ExpressSchema::Type to a category predicate.
    #
    # @param type [Symbol]
    # @return [Symbol]
    def category_key(type)
      case type
      when :resource then :resource?
      when :module_arm, :module_mim then :module?
      else :other?
      end
    end

    # Build a single section entry from a schema descriptor.
    #
    # @param schema [Hash{id:, path:, type:}]
    # @return [Hash]
    def build_section(schema)
      {
        "id" => schema[:id],
        "names" => {
          @language_code => SchemaNaming.prefixed_name(
            schema[:id], path: schema[:path],
          ),
        },
      }
    end

    # Build the complete register data structure.
    #
    # @param sections [Array<Hash>]
    # @return [Hash]
    def build_register(sections)
      {
        "schema_type" => "glossarist",
        "schema_version" => "3",
        "id" => @id,
        "ref" => @ref,
        "urn" => @urn.sub(/:\*$/, ""),
        "urnAliases" => [@urn],
        "status" => "current",
        "owner" => "ISO/TC 184/SC 4",
        "languages" => [@language_code],
        "ordering" => "systematic",
        "sections" => sections,
      }
    end
  end
end
