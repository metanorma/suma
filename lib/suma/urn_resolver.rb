# frozen_string_literal: true

require "json"
require "fileutils"
require "expressir"
require "glossarist"
# Expressir::SchemaManifest references Pathname without requiring it.
require "pathname"

module Suma
  # Resolves URNs to canonical JSON + HTML artifacts.
  #
  # Sources:
  # - schema manifest: schema and declared-element URNs
  # - Glossarist concept documents: term URNs
  # - register.yaml: the dataset URN
  #
  # Artifacts are written under the output directory by URN path, so every
  # URN emitted by a register (and every entity in the corpus) has a static,
  # dereferenceable document without a server.
  class UrnResolver
    class NotFoundError < Error; end

    attr_reader :urn

    # @param manifest_file [String] schema manifest path
    # @param urn [String, nil] corpus URN base; required unless a register
    #   supplies one
    # @param concepts_dir [String, nil] directory of Glossarist concept YAML
    # @param register_file [String, nil] Glossarist register.yaml
    def initialize(manifest_file:, urn: nil, concepts_dir: nil,
                   register_file: nil)
      @manifest_file = File.expand_path(manifest_file)
      @register_file = register_file && File.expand_path(register_file)
      @concepts_dir = concepts_dir && File.expand_path(concepts_dir)
      @urn = urn && Urn.new(urn)
      load_register if @register_file
    end

    # @return [Hash{String=>Hash}] URN → artifact payload
    def artifacts
      @artifacts ||= schema_artifacts
        .merge(concept_artifacts)
        .merge(dataset_artifacts)
    end

    # @param urn [String]
    # @return [Hash] artifact payload
    # @raise [NotFoundError]
    def resolve(urn)
      artifacts[normalize(urn)] || raise(
        NotFoundError, "urn does not resolve: #{urn}"
      )
    end

    # Write JSON and HTML for every artifact, plus an index of the set.
    def write(output_directory)
      artifacts.each_key { |key| write_urn(key, output_directory) }
      FileUtils.mkdir_p(output_directory)
      File.write(File.join(output_directory, "index.html"),
                 index_document, encoding: "utf-8")
      Utils.log "Wrote #{artifacts.length} URN artifacts to #{output_directory}"
    end

    # Write JSON and HTML for one URN.
    def write_urn(urn, output_directory)
      payload = resolve(urn)
      json = canonical_json(payload)
      write_file(output_directory, urn, "json", json)
      write_file(output_directory, urn, "html", html_document(urn, json))
    end

    private

    def normalize(value)
      value.to_s.delete_suffix(":*")
    end

    def base_urn
      @urn&.to_s || @register_urn
    end

    def compose(component, leaf)
      "#{base_urn}:#{component}:#{leaf}"
    end

    def load_register
      @register = Glossarist::DatasetRegister.from_file(@register_file)
      @register_urn = @register.urn
      @urn ||= Urn.new(@register_urn) if @register_urn
    end

    def schema_artifacts
      return {} unless base_urn

      artifacts = {}
      schemas.each do |schema|
        artifacts[compose(:tech, schema.id)] = schema_payload(schema)
        schema.children.each do |element|
          payload = element_payload(schema, element)
          artifacts[compose(:tech, "#{schema.id}.#{element.id}")] = payload if
            payload
          add_attribute_artifacts(artifacts, schema, element)
        end
      end
      artifacts
    end

    # Attribute property IRIs appear in the OWL projection as
    # <schema>.<entity>.<attribute>; make them dereferenceable too.
    def add_attribute_artifacts(artifacts, schema, element)
      return unless element.is_a?(Expressir::Model::Declarations::Entity)

      element.attributes.each do |attribute|
        key = compose(:tech,
                      "#{schema.id}.#{element.id}.#{attribute.id}")
        artifacts[key] = attribute_artifact(schema, element, attribute)
      end
    end

    def attribute_artifact(schema, entity, attribute)
      {
        "urn" => compose(:tech, "#{schema.id}.#{entity.id}.#{attribute.id}"),
        "kind" => "attribute",
        "schema" => schema.id,
        "entity" => entity.id,
        "id" => attribute.id,
        "attribute_kind" => attribute.kind,
        "optional" => attribute.optional == true,
        "type" => attribute.type&.source,
        "source" => relative_source(schema),
      }
    end

    def schemas
      @schemas ||= begin
        manifest = Expressir::SchemaManifest.from_file(@manifest_file)
        manifest.schemas.flat_map do |entry|
          Expressir::Express::Parser.from_file(entry.path.to_s).schemas
        end
      end
    end

    def schema_payload(schema)
      {
        "urn" => compose(:tech, schema.id),
        "kind" => "schema",
        "id" => schema.id,
        "source" => relative_source(schema),
        "interface" => Array(schema.interfaces).filter_map do |interface|
          interface.schema&.id
        end,
        "elements" => schema.children.filter_map do |element|
          element.id if declared_element?(element)
        end.sort,
      }
    end

    def element_payload(schema, element)
      case element
      when Expressir::Model::Declarations::Entity
        entity_payload(schema, element)
      when Expressir::Model::Declarations::Type
        type_payload(schema, element)
      end
    end

    def entity_payload(schema, entity)
      {
        "urn" => compose(:tech, "#{schema.id}.#{entity.id}"),
        "kind" => "entity",
        "schema" => schema.id,
        "id" => entity.id,
        "abstract" => entity.abstract,
        "source" => relative_source(schema),
        "subtype_of" => Array(entity.subtype_of).filter_map(&:id),
        "attributes" => Array(entity.attributes).map do |attribute|
          attribute_payload(attribute)
        end,
        "where_rules" => Array(entity.where_rules).map(&:id),
      }
    end

    def type_payload(schema, type)
      {
        "urn" => compose(:tech, "#{schema.id}.#{type.id}"),
        "kind" => "type",
        "schema" => schema.id,
        "id" => type.id,
        "source" => relative_source(schema),
        "underlying" => type.underlying_type.class.name.split("::").last,
        "where_rules" => Array(type.where_rules).map(&:id),
      }
    end

    def attribute_payload(attribute)
      {
        "id" => attribute.id,
        "kind" => attribute.kind,
        "optional" => attribute.optional == true,
        "type" => attribute.type&.source,
      }
    end

    def declared_element?(element)
      element.is_a?(Expressir::Model::Declarations::Entity) ||
        element.is_a?(Expressir::Model::Declarations::Type)
    end

    def relative_source(schema)
      return nil unless schema.file

      Pathname.new(schema.file.to_s)
        .relative_path_from(Pathname.new(File.dirname(@manifest_file)))
        .to_s
    rescue ArgumentError
      schema.file.to_s
    end

    def concept_artifacts
      return {} unless @concepts_dir && base_urn
      return {} unless Dir.exist?(@concepts_dir)

      Dir[File.join(@concepts_dir,
                    "*.yaml")].each_with_object({}) do |path, map|
        document = Glossarist::V3::ConceptDocument.from_yamls(File.read(path))
        concept = document.concept
        next unless concept

        key = compose(:term, concept.data.id)
        map[key] = concept_payload(concept, document)
      end
    end

    def concept_payload(concept, document)
      {
        "urn" => compose(:term, concept.data.id),
        "kind" => "concept",
        "id" => concept.data.id,
        "uuid" => concept.uuid,
        "domain" => concept.data.domains&.first&.concept_id,
        "localizations" => document.localizations.map do |localized|
          localization_payload(localized)
        end,
      }
    end

    def localization_payload(localized)
      data = localized.data
      {
        "language" => data.language_code,
        "terms" => Array(data.terms).map(&:designation),
        "definitions" => Array(data.definition).map(&:content),
        "notes" => Array(data.notes).map(&:content),
        "sources" => Array(data.sources).map do |source|
          source_payload(source)
        end,
      }
    end

    def source_payload(source)
      {
        "id" => source.id,
        "type" => source.type,
        "source" => source.origin&.ref&.source,
        "version" => source.origin&.ref&.version,
        "sourced_from" => Array(source.sourced_from).map do |citation|
          citation.ref&.source
        end,
      }
    end

    def dataset_artifacts
      return {} unless @register

      {
        normalize(@register.urn) => {
          "urn" => @register.urn,
          "kind" => "dataset",
          "id" => @register.id,
          "ref" => @register.ref,
          "year" => @register.year,
          "supersedes" => @register.supersedes,
          "tags" => @register.tags,
          "sections" => Array(@register.sections).map do |s|
            section_payload(s)
          end,
        },
      }
    end

    def section_payload(section)
      {
        "id" => section.id,
        "name" => section.name("eng"),
        "children" => Array(section.children).map { |s| section_payload(s) },
      }
    end

    # Deterministic documents: sorted object keys, trailing newline.
    def canonical_json(value)
      "#{JSON.pretty_generate(canonicalize(value))}\n"
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.sort.to_h { |key| [key, canonicalize(value[key])] }
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end

    def write_file(output_directory, urn, extension, content)
      path = File.join(output_directory, artifact_path(urn, extension))
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content, encoding: "utf-8")
    end

    def artifact_path(urn, extension)
      segments = normalize(urn).split(":").map do |segment|
        segment.gsub(/[^A-Za-z0-9._-]/, "_")
      end
      "#{segments.join('/')}.#{extension}"
    end

    def html_document(urn, json)
      title = escape_html(urn)
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><title>#{title}</title></head>
        <body>
        <h1>#{title}</h1>
        <pre>#{escape_html(json)}</pre>
        </body>
        </html>
      HTML
    end

    # A deterministic index of every resolved URN, linked to its document.
    def index_document
      items = artifacts.keys.sort.map do |urn|
        href = artifact_path(urn, "html")
        %(    <li><a href="#{escape_html(href)}">#{escape_html(urn)}</a></li>)
      end.join("\n")
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><title>Resolved URNs</title></head>
        <body>
        <h1>Resolved URNs</h1>
        <ul>
        #{items}
        </ul>
        </body>
        </html>
      HTML
    end

    def escape_html(value)
      value.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
        .gsub('"', "&quot;")
    end
  end
end
