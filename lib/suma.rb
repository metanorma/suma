# frozen_string_literal: true

require "expressir"
require "lutaml/model"
require "fileutils"

module Suma
  autoload :VERSION, "suma/version"

  autoload :SchemaProfile,          "suma/schema_profile"
  autoload :BuildPlan,              "suma/build_plan"
  autoload :Processor,              "suma/processor"
  autoload :Provenance,             "suma/provenance"
  autoload :Publication,            "suma/publication"
  autoload :ChangeClassification,   "suma/change_classification"
  autoload :ChangeImpact,           "suma/change_impact"
  autoload :ChangeManifest,         "suma/change_manifest"
  autoload :ClosureValidator,       "suma/closure_validator"
  autoload :CollectionConfig,       "suma/collection_config"
  autoload :CorpusGraph,            "suma/corpus_graph"
  autoload :CollectionManifest,     "suma/collection_manifest"
  autoload :EengineConverter,       "suma/eengine_converter"
  autoload :ExpressReformatter,     "suma/express_reformatter"
  autoload :ExpressSchema,          "suma/express_schema"
  autoload :LinkValidation,         "suma/link_validation"
  autoload :LinkValidator,          "suma/link_validator"
  autoload :ManifestTraverser,      "suma/manifest_traverser"
  autoload :MappingDrift,           "suma/mapping_drift"
  autoload :NoteProcessor,          "suma/note_processor"
  autoload :NullCache,              "suma/null_cache"
  autoload :OwlProjection,          "suma/owl_projection"
  autoload :RegisterManifestGenerator, "suma/register_manifest_generator"
  autoload :SchemaCache,            "suma/schema_cache"
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
  autoload :StagedCollectionBuilder, "suma/staged_collection_builder"
  autoload :SvgQuality,             "suma/svg_quality"
  autoload :TermClassification,     "suma/term_classification"
  autoload :TermExtractor,          "suma/term_extractor"
  autoload :ThorExt,                "suma/thor_ext"
  autoload :Urn,                    "suma/urn"
  autoload :UrnResolver,            "suma/urn_resolver"
  autoload :Utils,                  "suma/utils"
  autoload :WorkerPool,             "suma/worker_pool"

  autoload :Cli, "suma/cli"
  autoload :Eengine, "suma/eengine"
  autoload :Jsdai, "suma/jsdai"

  class Error < StandardError; end
  class SchemaNotFoundError < Error; end
  class CompilationError < Error; end
  class EengineNotAvailableError < Error; end
end
