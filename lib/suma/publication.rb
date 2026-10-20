# frozen_string_literal: true

require "expressir"

module Suma
  # An application-protocol publication bundle: a lead schema (the AP's
  # ARM/MIM) plus the transitive closure of the schemas it USEs FROM or
  # REFERENCEs, resolved against a schema manifest.
  #
  # The closure is computed from the parsed EXPRESS interfaces
  # (Expressir `Schema#interfaces`, `Interface#schema.id`), so the bundle
  # mirrors what a STEP publication actually ships: one AP volume with
  # every schema its AP needs.
  #
  # @example
  #   publication = Publication.new(
  #     lead_id: "ap242_foo_mim",
  #     schema_manifest_file: "schemas.yaml",
  #   )
  #   publication.schemas.each { |s| s.save_exp }
  class Publication
    attr_reader :lead_id, :schema_manifest_file, :profile

    # @param lead_id [String] schema id of the publication's lead schema
    # @param schema_manifest_file [String] path to the schema manifest
    # @param profile [SchemaProfile, Symbol, String, nil] schema profile
    def initialize(lead_id:, schema_manifest_file:, profile: nil)
      @lead_id = lead_id
      @schema_manifest_file = schema_manifest_file
      @profile = SchemaProfile.fetch(profile)
    end

    # The bundle's schemas, lead first, then breadth-first over the
    # interface closure.
    #
    # @param output_path [String] directory the caller will export into
    # @return [Array<ExpressSchema>]
    # @raise [Suma::SchemaNotFoundError] when the lead or a dependency is
    #   absent from the manifest
    def schemas(output_path: ".")
      entries = load_entries
      resolve(lead_id, entries, output_path)
    end

    private

    def load_entries
      manifest = Expressir::SchemaManifest.from_file(
        File.expand_path(schema_manifest_file),
      )
      manifest.schemas.to_h do |entry|
        [entry.id, entry]
      end
    end

    def resolve(lead, entries, output_path)
      closure_ids(lead, entries).map do |id|
        build_schema(id, entries, output_path)
      end
    end

    # Breadth-first ids of the interface closure reachable from +lead+.
    #
    # @param lead [String]
    # @param entries [Hash{String => Expressir::SchemaManifestEntry}]
    # @return [Array<String>] lead first, then closure order
    def closure_ids(lead, entries)
      order = []
      queue = [lead]
      until queue.empty?
        id = queue.shift
        next if order.include?(id)

        order << id
        queue.concat(interface_ids(id, entries))
      end
      order
    end

    # Interface (USE FROM / REFERENCE) schema ids declared by one schema.
    #
    # @param id [String]
    # @param entries [Hash{String => Expressir::SchemaManifestEntry}]
    # @return [Array<String>]
    def interface_ids(id, entries)
      schema = build_schema(id, entries, ".")
      dependency_ids(schema)
    end

    def build_schema(id, entries, output_path)
      entry = entries.fetch(id) do
        raise SchemaNotFoundError,
              "[suma] schema #{id.inspect} (needed by publication " \
              "#{lead_id.inspect}) not found in #{schema_manifest_file}"
      end
      ExpressSchema.new(id: id, path: entry.path,
                        output_path: output_path,
                        is_standalone_file: true,
                        profile: profile)
    end

    def dependency_ids(schema)
      parsed = schema.parsed
      schema_obj = parsed.schemas.first
      (schema_obj.interfaces || []).filter_map { |i| i.schema&.id }.uniq
    end
  end
end
