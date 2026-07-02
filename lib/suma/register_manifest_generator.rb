# frozen_string_literal: true

require "yaml"
require "pathname"
require "expressir"
require "glossarist"

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
  #   - Sections: built from Glossarist::Section models (model-driven)
  #   - URN semantics: delegates to Suma::Urn (OCP)
  #
  # @example
  #   generator = RegisterManifestGenerator.new(
  #     "schemas-smrl-part-2.yml",
  #     urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
  #     id: "iso10303-2-express",
  #     ref: "ISO 10303-2 EXPRESS Concepts",
  #   )
  #   generator.generate  # writes register.yaml
  class RegisterManifestGenerator
    DEFAULT_OWNER = "ISO/TC 184/SC 4"
    DEFAULT_STATUS = "current"
    DEFAULT_ORDERING = "systematic"
    DEFAULT_SCHEMA_TYPE = "glossarist"
    DEFAULT_SCHEMA_VERSION = "3"

    # @param schema_manifest_file [String] path to schemas-smrl-part-2.yml
    # @param output_path [String] directory to write register.yaml
    # @param urn [String] base URN for the dataset
    # @param id [String] dataset identifier
    # @param ref [String] human-readable reference label
    # @param language_code [String] language for section names
    # @param owner [String] dataset owner organisation
    def initialize(schema_manifest_file, output_path, urn:, id:, ref:,
                   language_code: "eng", owner: DEFAULT_OWNER)
      @schema_manifest_file = File.expand_path(schema_manifest_file)
      @output_path = output_path
      @urn = Suma::Urn.new(urn)
      @id = id
      @ref = ref
      @language_code = language_code
      @owner = owner
    end

    # Generate and write register.yaml.
    #
    # @return [Glossarist::DatasetRegister] the generated register
    def generate
      validate_inputs
      schemas = load_schemas
      register = build_register(schemas)

      FileUtils.mkdir_p(@output_path)
      output_file = File.join(@output_path, "register.yaml")
      File.write(output_file, register.to_yaml)
      Utils.log "Generated register.yaml: #{output_file}"
      Utils.log "  #{schemas.length} schemas in #{register.sections.length} categories"

      register
    end

    private

    # Verify that the manifest path exists, is a regular file, and contains
    # at least one schema entry. Called from {#generate} so both the CLI
    # shell and direct construction get the same validation behavior.
    #
    # @raise [Errno::ENOENT] when the manifest path is missing or not a file
    # @raise [ArgumentError] when the manifest is empty
    def validate_inputs
      unless File.exist?(@schema_manifest_file)
        raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                             "`#{@schema_manifest_file}` not found."
      end
      unless File.file?(@schema_manifest_file)
        raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                             "`#{@schema_manifest_file}` is not a file."
      end
    end

    # Load all schemas from the manifest file as SchemaManifestEntry models.
    #
    # @return [Array<Expressir::SchemaManifestEntry>]
    def load_schemas
      manifest = Expressir::SchemaManifest.from_file(@schema_manifest_file)
      schemas = manifest.schemas.sort_by { |s| s.id.downcase }
      if schemas.empty?
        raise ArgumentError, "No schemas found in manifest " \
                             "`#{@schema_manifest_file}`."
      end
      schemas
    end

    # Build a fully-populated DatasetRegister model.
    #
    # @param schemas [Array<Expressir::SchemaManifestEntry>]
    # @return [Glossarist::DatasetRegister]
    def build_register(schemas)
      Glossarist::DatasetRegister.new(
        schema_type: DEFAULT_SCHEMA_TYPE,
        schema_version: DEFAULT_SCHEMA_VERSION,
        id: @id,
        ref: @ref,
        urn: @urn.to_s,
        urn_aliases: @urn.aliases,
        status: DEFAULT_STATUS,
        owner: @owner,
        languages: [@language_code],
        ordering: DEFAULT_ORDERING,
        sections: build_sections(schemas),
      )
    end

    # Build a list of top-level sections, one per category, in
    # SchemaCategory::ALL declaration order. Categories with no
    # schemas are omitted.
    #
    # @param schemas [Array<Expressir::SchemaManifestEntry>]
    # @return [Array<Glossarist::Section>]
    def build_sections(schemas)
      groups = schemas.group_by do |s|
        SchemaCategory.for_schema(id: s.id, path: s.path)
      end

      SchemaCategory::ALL.filter_map do |category|
        children = groups[category] || []
        next if children.empty?

        Glossarist::Section.new(
          id: category.id,
          names: { @language_code => category.label },
          children: children.map { |s| build_section(s) },
        )
      end
    end

    # Build a single leaf section from a schema descriptor.
    #
    # @param schema [Expressir::SchemaManifestEntry]
    # @return [Glossarist::Section]
    def build_section(schema)
      Glossarist::Section.new(
        id: schema.id,
        names: {
          @language_code => SchemaNaming.prefixed_name(
            schema.id, path: schema.path
          ),
        },
      )
    end
  end
end
