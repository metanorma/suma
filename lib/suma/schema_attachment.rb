# frozen_string_literal: true

require "fileutils"
# require "metanorma/cli"
require_relative "schema_config"

module Suma
  class SchemaAttachment
    attr_accessor :schema, :output_path, :config

    def initialize(schema:, output_path:)
      @schema = schema
      @id = schema.id
      @output_path = output_path
    end

    def output_extensions
      "xml,html"
    end

    def to_adoc(path_to_schema_yaml)
      <<~HEREDOC
        = #{@id}
        :lutaml-express-index: schemas; #{path_to_schema_yaml};
        :bare: true
        :mn-document-class: iso
        :mn-output-extensions: #{output_extensions}

        [lutaml,schemas,context]
        ----
        {% for schema in context.schemas %}

        [%unnumbered]
        == #{@id}

        [source%unnumbered]
        --
        {{ schema.formatted }}
        --
        {% endfor %}
        ----

      HEREDOC
    end

    def filename_adoc(ext = "adoc")
      File.join(@output_path, "doc_#{@schema.id}.#{ext}")
    end

    def save_adoc
      relative_path = Pathname.new(filename_adoc).relative_path_from(Dir.pwd)
      Utils.log "Save EXPRESS adoc: #{relative_path}"

      # return if File.exist?(filename_adoc)
      FileUtils.mkdir_p(File.dirname(filename_adoc))

      relative_path = Pathname.new(filename_config)
                              .relative_path_from(Pathname.new(File.dirname(filename_adoc)))

      # Utils.log "relative_path #{relative_path}"

      File.open(filename_adoc, "w") do |file|
        file.write(to_adoc(relative_path))
      end
    end

    def filename_config
      File.join(@output_path, "schema_#{@schema.id}.yaml")
    end

    def to_config
      # return @config unless @config
      @config = SchemaConfig::Config.new
      @config.schemas << SchemaConfig::Schema.new(
        id: @schema.id,
        path: @schema.path
      )

      @config
    end

    def save_config
      relative_path = Pathname.new(filename_config).relative_path_from(Dir.pwd)
      Utils.log "Save schema config: #{relative_path}"

      # return if File.exist?(filename_config)
      FileUtils.mkdir_p(File.dirname(filename_config))

      File.open(filename_config, "w") do |file|
        file.write(to_config.to_yaml)
      end
    end

    # Compile Metanorma adoc per EXPRESS schema
    def compile
      # I am commenting out because I'm playing with the schemas-only status
      # return self if File.exist?(output_xml_path)

      save_config
      save_adoc

      relative_path = Pathname.new(filename_adoc).relative_path_from(Dir.pwd)
      Utils.log "Compiling schema #{relative_path}..."
      Metanorma::Compile.new.compile(
        filename_adoc,
        agree_to_terms: true,
        no_install_fonts: true
      )
      Utils.log "Compiling schema #{filename_adoc}...done!"

      # clean_artifacts

      # filename_adoc('xml')
      self
    end

    def output_xml_path
      filename_adoc("xml")
    end

    def clean_artifacts
      [
        filename_config,
        filename_adoc,
        filename_adoc("presentation.xml"),
        filename_adoc("adoc.lutaml.log.txt"),
        filename_adoc("err.html")
      ].each do |filename|
        FileUtils.rm_rf(filename)
      end
    end

    def output_folder; end
  end
end
