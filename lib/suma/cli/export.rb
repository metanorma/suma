# frozen_string_literal: true

require "thor"
require "pathname"

module Suma
  module Cli
    # Export command. Thin Thor adapter that constructs
    # +Suma::ExpressSchema+ instances from manifest entries or
    # standalone +.exp+ files, then delegates the actual writing to
    # +Suma::SchemaExporter+.
    #
    # The schema-type → output-subdirectory mapping lives in
    # +Suma::SchemaCategory+, the single source of truth. The exporter
    # itself never classifies — it consumes loaded ExpressSchema
    # objects whose output paths were set by this adapter.
    #
    # With +--publication SCHEMA_ID+, exports an application-protocol
    # publication bundle instead: the lead schema plus the transitive
    # USE-FROM/REFERENCE closure (+Suma::Publication+), written flat
    # under +<output>/<lead_id>/+.
    class Export < Thor
      desc "export *FILES",
           "Export EXPRESS schemas from manifest files or " \
           "standalone EXPRESS files"
      option :output, type: :string, aliases: "-o", required: true,
                      desc: "Output directory path"
      option :annotations, type: :boolean, default: false,
                           desc: "Include annotations (remarks/comments)"
      option :zip, type: :boolean, default: false,
                   desc: "Create ZIP archive of exported schemas"
      option :publication, type: :string, banner: "SCHEMA_ID",
                           desc: "Export an AP publication bundle: the " \
                                 "lead schema plus its transitive " \
                                 "USE-FROM/REFERENCE closure (manifest " \
                                 "input only)"
      option :profile, type: :string, default: "iso10303",
                       desc: "Corpus profile (iso10303 or generic)"

      def export(*files)
        require "expressir"

        validate_files(files)
        run(files, options)
      end

      private

      def validate_files(files)
        if files.empty?
          raise ArgumentError, "At least one file must be specified"
        end

        files.each do |file|
          unless File.exist?(file)
            raise Errno::ENOENT, "Specified file `#{file}` not found."
          end
        end
      end

      def run(files, options)
        schemas = if options[:publication]
                    publication_bundle(files, options)
                  else
                    files.flat_map { |file| build_schemas(file, options) }
                  end
        run_exporter(schemas, options)
      end

      def run_exporter(schemas, options)
        exporter = SchemaExporter.new(
          schemas: schemas,
          output_path: options[:output],
          options: {
            annotations: options[:annotations],
            create_zip: options[:zip],
          },
        )
        exporter.export
      end

      # Build the publication bundle schemas, rooted at
      # <output>/<lead_id>/ so the AP volume lands in its own directory.
      def publication_bundle(files, options)
        validate_bundle_input!(files)
        lead_id = options[:publication]
        publication = Publication.new(
          lead_id: lead_id,
          schema_manifest_file: files.first,
          profile: options[:profile],
        )
        publication.schemas(output_path: output_root.join(lead_id).to_s)
      end

      def validate_bundle_input!(files)
        return if bundle_input?(files)

        raise ArgumentError,
              "--publication requires exactly one schema manifest file " \
              "(.yml/.yaml) as input"
      end

      def bundle_input?(files)
        files.length == 1 &&
          %w[.yml .yaml].include?(File.extname(files.first).downcase)
      end

      def build_schemas(file, options)
        case File.extname(file).downcase
        when ".yml", ".yaml"
          build_from_manifest(file, options)
        when ".exp"
          [build_standalone(file, options)]
        else
          raise ArgumentError, "Unsupported file type: #{file}. " \
                               "Only .yml, .yaml, and .exp files are " \
                               "supported."
        end
      end

      def build_from_manifest(file, options)
        manifest = Expressir::SchemaManifest.from_file(file)
        manifest.schemas.map do |entry|
          build_from_manifest_entry(entry, options)
        end
      end

      def build_from_manifest_entry(entry, options)
        category = SchemaCategory.for_schema(id: entry.id, path: entry.path,
                                             profile: options[:profile])
        ExpressSchema.new(
          id: entry.id,
          path: entry.path.to_s,
          output_path: output_root.join(category.directory).to_s,
          is_standalone_file: false,
          profile: options[:profile],
        )
      end

      def build_standalone(exp_file, options)
        ExpressSchema.new(
          id: nil,
          path: File.expand_path(exp_file),
          output_path: output_root.to_s,
          is_standalone_file: true,
          profile: options[:profile],
        )
      end

      def output_root
        Pathname.new(options[:output]).expand_path
      end

      def self.exit_on_failure?
        true
      end
    end
  end
end
