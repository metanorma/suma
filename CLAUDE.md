# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Suma is a Ruby gem for processing EXPRESS schemas (ISO 10303 STEP standards). It reads Metanorma site manifests, discovers EXPRESS schemas, compiles them into documentation, and can export/compare schemas.

## Commands

### Development

```bash
bundle install              # Install dependencies
rake spec                   # Run RSpec tests
rake rubocop                # Run RuboCop linter
rake                        # Run both tests and linter (default task)
rspec spec/path/to_spec.rb  # Run a single spec file
rspec spec/path/to_spec.rb:42  # Run a single test at line 42
```

### CLI usage

```bash
exe/suma build METANORMA_YAML                          # Build collection from site manifest
exe/suma export -o OUTPUT_DIR schema1.yml schema2.exp  # Export schemas (YAML manifest or .exp files)
exe/suma compare TRIAL_SCHEMA REFERENCE_SCHEMA -v VER  # Compare schemas, generate .changes.yaml
exe/suma reformat PATH                                  # Reformat EXP files (use -r for recursive)
exe/suma generate-schemas METANORMA_YAML SCHEMAS_YAML  # Generate schema manifest from site manifest
exe/suma extract-terms SCHEMA_YAML GLOSSARIST_DIR -u URN   # Extract EXPRESS entity concepts to Glossarist v3 format
exe/suma generate-register SCHEMA_YAML OUT_DIR -u URN --id ID --ref REF  # Generate hierarchical register.yaml from schema manifest
exe/suma validate links SCHEMAS_FILE DOCS_PATH          # Validate EXPRESS cross-reference links
```

## Architecture

### Core pipeline (build command)

1. `Processor.new(...).run` receives a Metanorma site manifest YAML
2. `SiteConfig` reads the site manifest, finds collection YAML paths
3. `CollectionConfig` extends `Metanorma::Collection::Config` with a `CollectionManifest` that discovers `schemas.yaml` files
4. `ManifestTraverser` walks the manifest tree (`expand_schemas_only`, `export_schema_config`, `remove_schemas_only_sources`); `SchemaDiscovery` loads each `schemas.yaml` and builds doc sub-trees
5. `SchemaCollection` loads all discovered schemas via `Expressir`, exports plain `.exp` files, and compiles documentation via `SchemaCompiler` + `SchemaTemplate::Plain|Document` (Metanorma `.adoc` → XML/HTML)
6. `SchemaExporter` handles exporting schemas to a directory (with optional ZIP packaging)

### Key classes

- **`ExpressSchema`** — wraps a single EXPRESS schema file; parses via `Expressir::Express::Parser`, can output plain or annotated `.exp`. Includes nested `Type` module for schema classification (resource/module_arm/module_mim/business_object_model/core_model/standalone) based on ID suffixes and path segments
- **`SchemaCategory`** — value object mapping `ExpressSchema::Type` to a register/export category (id, label, prefix, types, directory). Single source of truth for category identity across `SchemaExporter`, `SchemaNaming`, and `RegisterManifestGenerator`
- **`Urn`** — value object encapsulating ISO URN semantics (wildcard stripping, base/alias split, leaf composition for `for_schema`/`for_term`/`for_entity`)
- **`TermExtractor`** — extracts EXPRESS entity concepts from a schema manifest into Glossarist v3 YAML format. Generates definitions with URN cross-references, processes remarks into notes, and resolves EXPRESS xrefs to URN mentions. Assigns stable UUIDv5 identifiers
- **`RegisterManifestGenerator`** (file: `lib/suma/register_manifest_generator.rb`) — generates a Glossarist v3 `register.yaml` with hierarchical sections from a schema manifest. Classifies schemas via `ExpressSchema::Type` (DRY), delegates naming to `SchemaNaming` (OCP), orders resources before modules. Uses the Section model's `children` field for hierarchy
- **`SchemaNaming`** — pure module that converts EXPRESS schema IDs to human-readable display names. Strips type suffixes (`_schema`/`_arm`/`_mim`/`_bom`), title-cases with acronym preservation (AIC, AEC, BREP, 2D, 3D…), lowercases function words, appends type labels (ARM/MIM)
- **`SchemaTemplate::Plain` / `SchemaTemplate::Document`** — pure renderers for the AsciiDoc body fed to Metanorma (no I/O, no schema knowledge). `Document` adds cross-reference anchors and produces XML-only output
- **`SchemaCompiler`** — orchestrates one schema's compilation: writes adoc + config, invokes `Metanorma::Compile`. Templates are injected via the constructor (composition over inheritance)
- **`SchemaCollection`** — orchestrates processing of all schemas from a config; selects `Plain` for top-level schemas and `Document` for schemas-only entries
- **`SchemaExporter`** — standalone export of schemas from manifest or `.exp` files to a directory, with optional ZIP
- **`CollectionManifest`** — pure data model (lutaml-model attributes + YAML mappings) for one node of a Metanorma collection manifest. No imperative methods
- **`ManifestTraverser`** — tree-walking service over a `CollectionManifest` (`find_schemas_only`, `export_schema_config`, `expand_schemas_only`, `remove_schemas_only_sources`)
- **`SchemaDiscovery`** — schema-config I/O service on a single manifest node (`load_config` from `schemas.yaml`, `build_doc_entries`, `build_added_manifest`)
- **`SchemaIndex`** — O(1) lookup index for schema and element names, used by `LinkValidator`
- **`LinkValidator`** — validates EXPRESS cross-reference links against a `SchemaIndex`; returns `LinkValidationResult` structs for unresolved links

### CLI structure

- `Suma::Cli::Core` (Thor subclass) — top-level CLI entrypoint
- Subcommands delegate to `Cli::Build`, `Cli::Export`, `Cli::Compare`, `Cli::Validate`, `Cli::Reformat`, `Cli::GenerateSchemas`, `Cli::ExtractTerms`, `Cli::GenerateRegister`, `Cli::ConvertJsdai`
- Thor extension (`ThorExt::Start`) adds `-h`/`--help` support and error formatting

### Terminology extraction (extract-terms / generate-register)

The `extract-terms` command reads an EXPRESS schema manifest, parses each `.exp` file via `Expressir`, and emits Glossarist v3 concept YAML with:
- Entity definitions using URN cross-references (`{{urn:...term,entity data type}}`, `{{urn:...term,entity}}`)
- Entity remarks processed into notes (first-sentence extraction, redundant note removal, invalid reference filtering)
- Domain classification via `ExpressSchema::Type` (resource vs application module)
- Section references for hierarchical grouping

The `generate-register` command reads the same schema manifest and emits `register.yaml` with hierarchical sections:
- Top-level groups: Resources (133) before Application Modules (1123)
- Child sections use human-readable names from `SchemaNaming` (e.g. "Resource: Topology", "Module: Activity (ARM)")
- Parent group IDs are included in concept metadata so the concept-browser can filter by group

### External dependencies

- **expressir** — EXPRESS schema parsing and manifest handling
- **metanorma** — document compilation (`.adoc` → XML/HTML/PDF)
- **lutaml-model** — YAML/XML model serialization (used in `SiteConfig`, `CollectionConfig`)
- **glossarist** — term extraction output format
- **eengine** (optional, external binary) — schema comparison via `Eengine::Wrapper`

### Schema comparison flow

The `compare` command uses an external `eengine` binary to diff two EXPRESS schemas, producing XML. `EengineConverter` then converts that XML into a `.changes.yaml` file managed by `Expressir::Changes::SchemaChange`.

## Code style

- Ruby 3.0+ with `frozen_string_literal: true` in every file
- RuboCop with performance, rake, and rspec plugins; inherits from riboseinc OSS guide
- Some CLI files are excluded from RuboCop in `.rubocop.yml`
- Internal library code uses Ruby `autoload` (defined in the immediate parent namespace's file); no `require_relative`
- No `send` to call private methods, no `instance_variable_set`/`get`, no `respond_to?` for type checking
- Use `Utils.log` for user-facing output (writes to `$stderr`, prefix `[suma]`; `level: :debug` gated by `SUMA_DEBUG`)
