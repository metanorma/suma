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

1. `Processor.run` receives a Metanorma site manifest YAML
2. `SiteConfig` reads the site manifest, finds collection YAML paths
3. `CollectionConfig` extends `Metanorma::Collection::Config` with a `CollectionManifest` that discovers `schemas.yaml` files
4. `SchemaCollection` loads all discovered schemas via `Expressir`, exports plain `.exp` files, and compiles documentation (Metanorma `.adoc` → XML/HTML)
5. `SchemaExporter` handles exporting schemas to a directory (with optional ZIP packaging)

### Key classes

- **`ExpressSchema`** — wraps a single EXPRESS schema file; parses via `Expressir::Express::Parser`, can output plain or annotated `.exp`. Includes nested `Type` module for schema classification (resource/module_arm/module_mim/business_object_model/core_model/standalone) based on ID suffixes and path segments
- **`TermExtractor`** — extracts EXPRESS entity concepts from a schema manifest into Glossarist v3 YAML format. Generates definitions with URN cross-references, processes remarks into notes, and resolves EXPRESS xrefs to URN mentions
- **`RegisterGenerator`** — generates a Glossarist v3 `register.yaml` with hierarchical sections from a schema manifest. Classifies schemas via `ExpressSchema::Type` (DRY), delegates naming to `SchemaNaming` (OCP), orders resources before modules. Uses the Section model's `children` field for hierarchy
- **`SchemaNaming`** — pure module that converts EXPRESS schema IDs to human-readable display names. Strips type suffixes (`_schema`/`_arm`/`_mim`/`_bom`), title-cases with acronym preservation (AIC, AEC, BREP, 2D, 3D…), lowercases function words, appends type labels (ARM/MIM)
- **`SchemaAttachment`** — compiles one schema into a Metanorma `.adoc` document and renders it via `Metanorma::Compile`
- **`SchemaDocument`** (extends `SchemaAttachment`) — adds cross-reference bookmarks and uses XML-only output
- **`SchemaCollection`** — orchestrates processing of all schemas from a config
- **`SchemaExporter`** — standalone export of schemas from manifest or `.exp` files to a directory, with optional ZIP
- **`CollectionManifest`** — traverses collection YAML files, builds unified `Expressir::SchemaManifest`

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
- Use `Utils.log` for user-facing output (prefixes with `[suma]`)
