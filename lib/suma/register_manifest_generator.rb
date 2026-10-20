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
    # @param profile [SchemaProfile, Symbol, String, nil] schema profile
    #   governing classification, naming, and category ordering
    # @param year [Integer, nil] edition year
    # @param supersedes [String, nil] URN/ref this edition supersedes
    # @param edition [Integer, nil] edition number (tagged as edition:N)
    def initialize(schema_manifest_file, output_path, urn:, id:, ref:,
                   language_code: "eng", owner: DEFAULT_OWNER, profile: nil,
                   year: nil, supersedes: nil, edition: nil)
      @schema_manifest_file = File.expand_path(schema_manifest_file)
      @output_path = output_path
      @urn = Suma::Urn.new(urn)
      @id = id
      @ref = ref
      @language_code = language_code
      @owner = owner
      @profile = SchemaProfile.fetch(profile)
      @year = year
      @supersedes = supersedes
      @edition = edition
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
        year: @year,
        supersedes: @supersedes,
        tags: edition_tags,
        sections: build_sections(schemas),
      )
    end

    # Edition metadata for the register: the edition number is carried as
    # a tag so consumers can group editions of one dataset.
    def edition_tags
      @edition ? ["edition:#{@edition}"] : []
    end

    # Build a list of top-level sections, one per category, in the
    # schema profile's category order. Categories with no schemas are
    # omitted.
    #
    # @param schemas [Array<Expressir::SchemaManifestEntry>]
    # @return [Array<Glossarist::Section>]
    def build_sections(schemas)
      groups = schemas.group_by do |s|
        SchemaCategory.for_schema(id: s.id, path: s.path, profile: @profile)
      end

      SchemaCategory.for_profile(@profile).filter_map do |category|
        children = groups[category] || []
        next if children.empty?

        Glossarist::Section.new(
          id: category.id,
          names: { @language_code => category.label },
          children: section_children(category, children),
        )
      end
    end

    # Application protocols are grouped one level deeper: the schemas of
    # one AP publication (its `_arm`/`_mim` pair) become the children of
    # a per-AP parent section, so the register mirrors the publication
    # bundling.
    #
    # @param category [SchemaCategory]
    # @param schemas [Array<Expressir::SchemaManifestEntry>]
    # @return [Array<Glossarist::Section>]
    def section_children(category, schemas)
      if category == SchemaCategory::APPLICATION_PROTOCOLS
        build_ap_publication_sections(schemas)
      else
        schemas.map { |s| build_section(s) }
      end
    end

    # Build one parent section per AP publication, keyed by the AP's
    # base identity (the schema id with its ARM/MIM suffix stripped).
    #
    # @param schemas [Array<Expressir::SchemaManifestEntry>]
    # @return [Array<Glossarist::Section>]
    def build_ap_publication_sections(schemas)
      schemas.group_by { |s| ap_base_id(s.id) }.sort_by { |base, _| base }
        .map do |base, members|
        Glossarist::Section.new(
          id: base,
          names: {
            @language_code => "Application Protocol: " \
                              "#{SchemaNaming.display_name(base, profile: @profile)}",
          },
          children: members.sort_by { |s| s.id.downcase }
            .map { |s| build_section(s) },
        )
      end
    end

    # Strip the ARM/MIM suffix to get the AP publication's base identity.
    #
    # @param id [String]
    # @return [String]
    def ap_base_id(id)
      %w[_arm _mim].each do |suffix|
        return id.delete_suffix(suffix) if id.downcase.end_with?(suffix)
      end
      id
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
            schema.id, path: schema.path, profile: @profile
          ),
        },
      )
    end
  end
end
