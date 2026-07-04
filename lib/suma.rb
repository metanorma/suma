# frozen_string_literal: true

require "expressir"
require "lutaml/model"

module Suma
  autoload :VERSION, "suma/version"

  autoload :Processor,              "suma/processor"
  autoload :CollectionConfig,       "suma/collection_config"
  autoload :CollectionManifest,     "suma/collection_manifest"
  autoload :EengineConverter,       "suma/eengine_converter"
  autoload :ExpressSchema,          "suma/express_schema"
  autoload :LinkValidator,          "suma/link_validator"
  autoload :ManifestTraverser,      "suma/manifest_traverser"
  autoload :RegisterManifestGenerator, "suma/register_manifest_generator"
  autoload :SchemaCategory,         "suma/schema_category"
  autoload :SchemaCollection,       "suma/schema_collection"
  autoload :SchemaComparer,         "suma/schema_comparer"
  autoload :SchemaCompiler,         "suma/schema_compiler"
  autoload :SchemaDiscovery,        "suma/schema_discovery"
  autoload :SchemaExporter,         "suma/schema_exporter"
  autoload :SchemaIndex,            "suma/schema_index"
  autoload :SchemaManifestGenerator, "suma/schema_manifest_generator"
  autoload :SchemaNaming,           "suma/schema_naming"
  autoload :SchemaTemplate,         "suma/schema_template"
  autoload :SiteConfig,             "suma/site_config"
  autoload :SvgQuality,             "suma/svg_quality"
  autoload :TermClassification,     "suma/term_classification"
  autoload :TermExtractor,          "suma/term_extractor"
  autoload :ThorExt,                "suma/thor_ext"
  autoload :Urn,                    "suma/urn"
  autoload :Utils,                  "suma/utils"

  autoload :Cli, "suma/cli"
  autoload :Eengine, "suma/eengine"
  autoload :Jsdai, "suma/jsdai"

  class Error < StandardError; end
  class SchemaNotFoundError < Error; end
  class CompilationError < Error; end
  class EengineNotAvailableError < Error; end
end
