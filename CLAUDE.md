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
exe/suma extract-terms SCHEMA_YAML GLOSSARIST_DIR      # Extract terms to Glossarist v2 format
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

- **`ExpressSchema`** — wraps a single EXPRESS schema file; parses via `Expressir::Express::Parser`, can output plain or annotated `.exp`
- **`SchemaAttachment`** — compiles one schema into a Metanorma `.adoc` document and renders it via `Metanorma::Compile`
- **`SchemaDocument`** (extends `SchemaAttachment`) — adds cross-reference bookmarks and uses XML-only output
- **`SchemaCollection`** — orchestrates processing of all schemas from a config
- **`SchemaExporter`** — standalone export of schemas from manifest or `.exp` files to a directory, with optional ZIP
- **`CollectionManifest`** — traverses collection YAML files, builds unified `Expressir::SchemaManifest`

### CLI structure

- `Suma::Cli::Core` (Thor subclass) — top-level CLI entrypoint
- Subcommands delegate to `Cli::Build`, `Cli::Export`, `Cli::Compare`, `Cli::Validate`, `Cli::Reformat`, `Cli::GenerateSchemas`, `Cli::ExtractTerms`, `Cli::ConvertJsdai`
- Thor extension (`ThorExt::Start`) adds `-h`/`--help` support and error formatting

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
