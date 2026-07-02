# frozen_string_literal: true

require "fileutils"
require "pathname"

module Suma
  # Orchestrates the compilation of a single EXPRESS schema into HTML/XML
  # via Metanorma.
  #
  # SchemaCompiler owns all file I/O and the Metanorma::Compile invocation
  # for one schema; the rendered AsciiDoc body is supplied by a SchemaTemplate
  # that the caller injects. This split means templates can be tested as pure
  # functions and the compiler can be tested with a real adoc fixture, without
  # either depending on the other.
  class SchemaCompiler
    attr_reader :schema, :id, :output_path, :template

    def initialize(schema:, output_path:, template:)
      @schema = schema
      @id = schema.id
      @output_path = output_path
      @template = template
    end

    def compile
      save_config
      save_adoc
      invoke_metanorma
      self
    end

    def output_xml_path
      filename_adoc("xml")
    end

    def extensions
      template.extensions
    end

    private

    def filename_adoc(ext = "adoc")
      File.join(output_path, "doc_#{id}.#{ext}")
    end

    def filename_config
      File.join(output_path, "schema_#{id}.yaml")
    end

    def save_adoc
      log_relative "Save EXPRESS adoc", filename_adoc

      FileUtils.mkdir_p(File.dirname(filename_adoc))

      config_relative = Pathname.new(filename_config)
        .relative_path_from(Pathname.new(File.dirname(filename_adoc)))

      File.write(filename_adoc, template.render(config_relative))
    end

    def save_config
      log_relative "Save schema config", filename_config

      FileUtils.mkdir_p(File.dirname(filename_config))
      config = Expressir::SchemaManifest.new
      config.schemas << Expressir::SchemaManifestEntry.new(id: id,
                                                           path: schema.path)
      config.save_to_path(filename_config)
    end

    def invoke_metanorma
      log_relative "Compiling schema (id: #{id})", filename_adoc
      Metanorma::Compile.new.compile(
        filename_adoc,
        agree_to_terms: true,
        install_fonts: false,
      )
      log_relative "Compiling schema (id: #{id}) ... done!", filename_adoc
    end

    def log_relative(prefix, path)
      relative = Pathname.new(path).relative_path_from(Dir.pwd)
      Utils.log "#{prefix}: #{relative}"
    end
  end
end
