# frozen_string_literal: true

module Suma
  # Value object mapping an ExpressSchema::Type to its register/export category.
  #
  # Single source of truth for category identity across the codebase:
  # directory layout (SchemaExporter), display prefix (SchemaNaming), and
  # register.yaml sections (RegisterManifestGenerator) all derive from this.
  #
  # Each category carries: +id+ (slug used in register.yaml section id and
  # export subdirectory), +label+ (human-readable section heading),
  # +prefix+ (prefix used when forming display names, e.g. "Resource: ..."),
  # +types+ (Array of ExpressSchema::Type symbols that belong to it),
  # and +directory+ (subdirectory name; "." for the root output path).
  class SchemaCategory
    attr_reader :id, :label, :prefix, :types, :directory

    def initialize(id:, label:, prefix:, types:, directory:)
      @id = id
      @label = label
      @prefix = prefix
      @types = types
      @directory = directory
    end

    def member?(type)
      types.include?(type)
    end

    RESOURCES = new(
      id: "resources",
      label: "Resources",
      prefix: "Resource",
      types: [ExpressSchema::Type::RESOURCE].freeze,
      directory: "resources",
    )
    MODULES = new(
      id: "modules",
      label: "Application Modules",
      prefix: "Module",
      types: [ExpressSchema::Type::MODULE_ARM, ExpressSchema::Type::MODULE_MIM].freeze,
      directory: "modules",
    )
    BUSINESS_OBJECT_MODELS = new(
      id: "business_object_models",
      label: "Business Object Models",
      prefix: "Business Object Model",
      types: [ExpressSchema::Type::BUSINESS_OBJECT_MODEL].freeze,
      directory: "business_object_models",
    )
    CORE_MODEL = new(
      id: "core_model",
      label: "Core Model",
      prefix: "Core Model",
      types: [ExpressSchema::Type::CORE_MODEL].freeze,
      directory: "core_model",
    )
    OTHER = new(
      id: "other",
      label: "Other Schemas",
      prefix: "Schema",
      types: [ExpressSchema::Type::STANDALONE].freeze,
      directory: ".",
    )

    ALL = [
      RESOURCES,
      MODULES,
      BUSINESS_OBJECT_MODELS,
      CORE_MODEL,
      OTHER,
    ].freeze

    def self.for_type(type)
      ALL.find { |category| category.member?(type) } || OTHER
    end

    def self.for_schema(id:, path:)
      type = ExpressSchema::Type.classify(id: id, path: path)
      for_type(type)
    end
  end
end
