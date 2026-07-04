# frozen_string_literal: true

module Suma
  # Term-extractor-specific classification of an EXPRESS schema.
  #
  # Bridges ExpressSchema::Type (the canonical classification shared
  # across the codebase) and the Glossarist-specific labels
  # TermExtractor emits: the domain string ("application module" /
  # "resource") that goes into a concept's +domain+ field, and the
  # entity-type URN term used in generated concept definitions.
  #
  # The mapping is data — a frozen Hash keyed by ExpressSchema::Type
  # symbol — so adding a new schema type is a one-line addition to
  # BY_TYPE (open/closed principle). The previous implementation
  # switched on string keys in three separate places; this consolidates
  # them into one source of truth.
  class TermClassification
    attr_reader :type, :domain_label, :entity_term, :entity_display

    def initialize(type:, domain_label:, entity_term:, entity_display:)
      @type = type
      @domain_label = domain_label
      @entity_term = entity_term
      @entity_display = entity_display
      freeze
    end

    def domain_for(schema_id)
      "#{domain_label}: #{schema_id}"
    end

    BY_TYPE = {
      ExpressSchema::Type::RESOURCE => new(
        type: ExpressSchema::Type::RESOURCE,
        domain_label: "resource",
        entity_term: "express-language.entity_data_type",
        entity_display: "entity data type",
      ),
      ExpressSchema::Type::MODULE_ARM => new(
        type: ExpressSchema::Type::MODULE_ARM,
        domain_label: "application module",
        entity_term: "general.application_object",
        entity_display: "application object",
      ),
      ExpressSchema::Type::MODULE_MIM => new(
        type: ExpressSchema::Type::MODULE_MIM,
        domain_label: "application module",
        entity_term: "express-language.entity_data_type",
        entity_display: "entity data type",
      ),
      ExpressSchema::Type::BUSINESS_OBJECT_MODEL => new(
        type: ExpressSchema::Type::BUSINESS_OBJECT_MODEL,
        domain_label: "resource",
        entity_term: "express-language.entity_data_type",
        entity_display: "entity data type",
      ),
      ExpressSchema::Type::CORE_MODEL => new(
        type: ExpressSchema::Type::CORE_MODEL,
        domain_label: "resource",
        entity_term: "express-language.entity_data_type",
        entity_display: "entity data type",
      ),
      ExpressSchema::Type::STANDALONE => new(
        type: ExpressSchema::Type::STANDALONE,
        domain_label: "resource",
        entity_term: "express-language.entity_data_type",
        entity_display: "entity data type",
      ),
    }.freeze

    def self.for_schema(id:, path:)
      type = ExpressSchema::Type.classify(id: id, path: path)
      BY_TYPE.fetch(type) do |t|
        raise Error, "[suma] no term classification for type #{t.inspect}"
      end
    end
  end
end
