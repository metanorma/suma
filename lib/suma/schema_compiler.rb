# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
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
  #
  # Rendering is skipped when the adoc, the schema config, the schema source,
  # and the rendering toolchain are unchanged since the outputs were written:
  # the render key is stored beside the outputs.
  class SchemaCompiler
    RENDER_KEY_FILE = ".suma-render-key"

    attr_reader :schema, :id, :output_path, :template

    def initialize(schema:, output_path:, template:, no_valid: false)
      @schema = schema
      @id = schema.id
      @output_path = output_path
      @template = template
      @no_valid = no_valid
    end

    def compile
      save_config
      adoc = template.render(config_relative_path)
      save_adoc(adoc)
      key = render_key(adoc)
      return reuse_render if rendered_current?(key)

      invoke_metanorma
      write_render_key(key)
      self
    end

    def output_xml_path
      filename_adoc("xml")
    end

    def extensions
      template.extensions
    end

    # Options handed to Metanorma::Compile. Exposed for specs.
    def compile_options
      { agree_to_terms: true, install_fonts: false }.tap do |options|
        options[:novalid] = true if @no_valid
      end
    end

    private

    def filename_adoc(ext = "adoc")
      File.join(output_path, "doc_#{id}.#{ext}")
    end

    def filename_config
      File.join(output_path, "schema_#{id}.yaml")
    end

    def render_key_path
      File.join(output_path, RENDER_KEY_FILE)
    end

    def config_relative_path
      Pathname.new(filename_config)
        .relative_path_from(Pathname.new(File.dirname(filename_adoc)))
    end

    def save_adoc(content)
      log_relative "Save EXPRESS adoc", filename_adoc

      FileUtils.mkdir_p(File.dirname(filename_adoc))
      File.write(filename_adoc, content)
    end

    def save_config
      log_relative "Save schema config", filename_config

      FileUtils.mkdir_p(File.dirname(filename_config))
      config = Expressir::SchemaManifest.new
      config.schemas << Expressir::SchemaManifestEntry.new(id: id,
                                                           path: schema.path)
      config.save_to_path(filename_config)
    end

    # Everything the rendered document depends on. The schema source is an
    # input even though the adoc references it only by path.
    def render_key(adoc)
      Digest::SHA256.hexdigest(
        [adoc, File.read(filename_config), schema_source_digest,
         JSON.generate(Provenance.render_toolchain)].join("\0"),
      )
    end

    def schema_source_digest
      path = schema.path.to_s
      File.file?(path) ? Digest::SHA256.file(path).hexdigest : "missing:#{path}"
    end

    def rendered_current?(key)
      File.file?(render_key_path) && File.read(render_key_path) == key &&
        expected_output_paths.all? { |path| File.file?(path) }
    end

    def expected_output_paths
      extensions.split(",").map { |ext| filename_adoc(ext.strip) }
    end

    def write_render_key(key)
      File.write(render_key_path, key)
    end

    def reuse_render
      log_relative "Reusing rendered schema doc (id: #{id})", filename_adoc
      self
    end

    def invoke_metanorma
      log_relative "Compiling schema (id: #{id})", filename_adoc
      Metanorma::Compile.new.compile(filename_adoc, **compile_options)
      verify_outputs!
      log_relative "Compiling schema (id: #{id}) ... done!", filename_adoc
    end

    # Metanorma::Compile#compile can return nil for a handled failure instead
    # of raising. Never cache a render that produced no output.
    def verify_outputs!
      missing = expected_output_paths.reject { |path| File.file?(path) }
      return if missing.empty?

      names = missing.map { |path| File.basename(path) }.join(", ")
      raise CompilationError,
            "Metanorma produced no #{names} for schema #{id}"
    end

    def log_relative(prefix, path)
      relative = Pathname.new(path).relative_path_from(Dir.pwd)
      Utils.log "#{prefix}: #{relative}"
    end
  end
end
