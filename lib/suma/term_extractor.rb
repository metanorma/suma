# frozen_string_literal: true

require "fileutils"
require "expressir"
require "glossarist"

module Suma
  class TermExtractor
    def initialize(schema_manifest_file, output_path, urn:,
                   language_code: "eng")
      @schema_manifest_file = File.expand_path(schema_manifest_file)
      @output_path = output_path
      @language_code = language_code
      @urn = Suma::Urn.new(urn)
    end

    def call
      validate_inputs
      get_exp_files.map do |exp_file|
        extract(exp_file)
      end
    end

    private

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

    def get_exp_files
      config = Expressir::SchemaManifest.from_file(@schema_manifest_file)
      paths = config.schemas.map(&:path)

      if paths.empty?
        raise Errno::ENOENT,
              "No EXPRESS files found in `#{@schema_manifest_file}`."
      end

      paths
    end

    def extract(exp_file)
      exp_path_rel = Pathname.new(exp_file).relative_path_from(Pathname.getwd)
      Utils.log "Building terms: #{exp_path_rel}"

      repo = Expressir::Express::Parser.from_file(exp_file)
      schema = repo.schemas.first

      raise Error, "Schema must have an associated file" unless schema.file

      classification = TermClassification.for_schema(id: schema.id,
                                                      path: schema.file)
      collection = build_managed_concept_collection(schema, classification)
      output_data(collection)
      collection
    end

    def output_data(collection)
      output_dir = File.expand_path(@output_path)
      FileUtils.mkdir_p(output_dir)
      Utils.log "Saving collection to files in: #{@output_path}"

      collection.each do |concept|
        doc = Glossarist::V3::ConceptDocument.from_managed_concept(concept)
        doc.localizations = concept.data.localizations.keys.map do |lang|
          concept.localization(lang)
        end

        filename = "#{concept.uuid.gsub(/[^\w.-]/, '_')}.yaml"
        File.write(File.join(output_dir, filename), doc.to_yamls,
                   encoding: "utf-8")
      end
    end

    def build_managed_concept_collection(schema, classification)
      source_ref = get_source_ref(schema)
      section_ref = get_section_ref(schema)

      Glossarist::ManagedConceptCollection.new.tap do |collection|
        schema.entities.each do |entity|
          localized_concept_id = Glossarist::Utilities::UUID.uuid_v5(
            Glossarist::Utilities::UUID::OID_NAMESPACE,
            "#{schema.id}.#{entity.id}-#{@language_code}",
          )

          localized_concept = build_localized_concept(
            schema: schema,
            entity: entity,
            source_ref: source_ref,
            uuid: localized_concept_id,
            classification: classification,
          )

          managed_data = Glossarist::V3::ManagedConceptData.new.tap do |data|
            data.id = "#{schema.id}.#{entity.id}"
            data.localizations.store(@language_code, localized_concept)
            data.localized_concepts = { @language_code => localized_concept_id }
            data.domains = [section_ref] if section_ref
          end

          managed_concept = Glossarist::V3::ManagedConcept.new.tap do |concept|
            concept.id = managed_data.id
            concept.uuid = Glossarist::Utilities::UUID.uuid_v5(
              Glossarist::Utilities::UUID::OID_NAMESPACE,
              managed_data.id,
            )
            concept.data = managed_data
            concept.schema_version = "v3"
          end

          collection.store(managed_concept)
        end
      end
    end

    def build_localized_concept(schema:, entity:, source_ref:, uuid:,
                                classification:)
      schema_domain = classification.domain_for(schema.id)

      localized_concept_data = Glossarist::V3::ConceptData.new.tap do |data|
        data.terms = get_entity_terms(entity)
        data.definition = get_entity_definitions(entity, schema, classification)
        data.language_code = @language_code
        data.domain = schema_domain
        data.sources = [source_ref] if source_ref

        notes = NoteProcessor.call(
          entity.remarks,
          definitions: data.definition,
          xref_to_mention: method(:xref_to_mention),
        )
        data.notes = notes if notes && !notes.empty?
        data.examples = []
      end

      Glossarist::V3::LocalizedConcept.new(
        data: localized_concept_data, uuid: uuid,
      )
    end

    def schema_urn(schema)
      @urn.for_schema(schema.id)
    end

    def term_urn(concept_identifier)
      @urn.for_term(concept_identifier)
    end

    def express_entity_urn(full_ref)
      @urn.for_entity(full_ref)
    end

    def urn_mention(urn, display)
      "{{#{urn},#{display}}}"
    end

    def xref_to_mention(full_ref, display)
      urn_mention(express_entity_urn(full_ref), display)
    end

    def get_section_ref(schema)
      return nil unless @urn

      Glossarist::ConceptReference.new(
        concept_id: "section-#{schema.id}",
        source: schema_urn(schema),
        ref_type: "section",
      )
    end

    def get_source_ref(schema)
      ref = Glossarist::Citation::Ref.new
      ref.source = schema_urn(schema)

      build_custom_locality(schema).each do |cl|
        case cl.name
        when "version" then ref.version = cl.value
        end
      end

      origin = Glossarist::V3::Citation.new
      origin.ref = ref
      Glossarist::V3::ConceptSource.new(id: schema.id, type: "authoritative",
                                        origin: origin)
    end

    def build_custom_locality(schema)
      localities = []

      version_item = schema.version.items.detect { |i| i.name == "version" }
      if version_item
        localities << Glossarist::CustomLocality.new(name: "version",
                                                     value: version_item.value)
      end

      localities
    end

    def get_entity_terms(entity)
      [
        Glossarist::Designation::Base.new(
          designation: entity.id,
          type: "expression",
          normative_status: "preferred",
        ),
      ]
    end

    def get_entity_definitions(entity, schema, classification)
      definition = generate_entity_definition(entity, schema, classification)
      [Glossarist::V3::DetailedDefinition.new(content: definition)]
    end

    def entity_name_to_text(entity_id)
      entity_id.downcase.gsub("_", " ")
    end

    def generate_entity_definition(entity, schema, classification)
      return "" if entity.nil?

      entity_type = urn_mention(
        term_urn(classification.entity_term),
        classification.entity_display,
      )

      entity_ref = urn_mention(term_urn("express-language.entity"), "entity")

      if entity.subtype_of.empty?
        "#{entity_type} " \
          "that represents the " \
          "#{entity_name_to_text(entity.id)} #{entity_ref}"
      else
        entity_subtypes = entity.subtype_of.map do |e|
          urn_mention(express_entity_urn("#{schema.id}.#{e.id}"), e.id)
        end

        "#{entity_type} that is a type of " \
          "#{entity_subtypes.join(' and ')} " \
          "that represents the " \
          "#{entity_name_to_text(entity.id)} #{entity_ref}"
      end
    end
  end
end
