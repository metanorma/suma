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
exe/suma build METANORMA_YAML --incremental --jobs 4   # Re-render changed schemas + dependents; parallel export
SUMA_SCHEMA_CACHE_DIR=.suma-cache exe/suma build METANORMA_YAML  # Reuse parsed models/outputs across builds
rake benchmark                                         # 1,000-schema synthetic corpus budget check
exe/suma build METANORMA_YAML --provenance provenance.json  # sha256 of inputs/outputs + toolchain
exe/suma build METANORMA_YAML --provenance provenance.json --sign sigstore  # optional signature (minisign|sigstore)
exe/suma export -o OUTPUT_DIR schema1.yml schema2.exp  # Export schemas (YAML manifest or .exp files)
exe/suma export -o OUTPUT_DIR --publication AP_LEADER_ID schemas.yaml  # Export an AP publication bundle (lead + USE-FROM closure)
exe/suma export --format owl -o OUT --urn BASE schemas.yaml  # Project the corpus to OWL/Turtle (one file per schema; add --corpus for a corpus ontology)
exe/suma compare TRIAL_SCHEMA REFERENCE_SCHEMA -v VER  # Compare schemas, generate .changes.yaml
exe/suma compare ... -v VER --typed-output FILE --changelog --impact --manifest SCHEMAS_YAML  # Typed change manifest, changelog, impact analysis
exe/suma reformat PATH                                  # Reformat EXP files (use -r for recursive)
exe/suma generate-schemas METANORMA_YAML SCHEMAS_YAML  # Generate schema manifest from site manifest
exe/suma extract-terms SCHEMA_YAML GLOSSARIST_DIR -u URN   # Extract EXPRESS entity concepts to Glossarist v3 format
exe/suma extract-terms ... --edition 3 --language-codes fra deu  # Provenance + linked localizations
exe/suma resolve URN --manifest SCHEMAS_YAML --concepts DIR --register register.yaml -o OUT  # Emit canonical JSON + HTML
exe/suma resolve --all --manifest SCHEMAS_YAML --concepts DIR --register register.yaml -o OUT  # Emit every URN artifact
exe/suma generate-register SCHEMA_YAML OUT_DIR -u URN --id ID --ref REF  # Generate hierarchical register.yaml from schema manifest
exe/suma validate links SCHEMAS_FILE DOCS_PATH          # Validate EXPRESS cross-reference links
exe/suma validate closure SCHEMAS_MANIFEST [DOCUMENTS_PATH]  # Referential closure: every reference resolves (exit 1 on violations)
```

## Schema profiles

Suma works with any schema collection. `Suma::SchemaProfile` declares how schema
identifiers and paths map to types (`ExpressSchema::Type`), how
identifiers become display names (`SchemaNaming`), and the ordered
register categories (`SchemaCategory`). Registered profiles: `iso10303`
(default; STEP conventions incl. `/applications/` → application
protocol) and `generic` (no STEP conventions). The CLI takes
`--profile` on `export`, `extract-terms`, and `generate-register`.

## ISO 10303 AP publications

An AP publication is a lead schema (the AP's ARM/MIM) bundled with the
module/resource schemas it USEs. `Suma::Publication` computes the
transitive USE-FROM/REFERENCE closure from the parsed EXPRESS interfaces
and resolves it against a schema manifest; `export --publication ID`
writes the bundle flat under `<output>/<lead_id>/`. In the register,
the "Application Protocols" category groups each AP's ARM/MIM under a
per-publication parent section.

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
- **`ChangeClassification` / `ChangeManifest` / `ChangeImpact`** — S3 typed change ontology: eengine actions are classified (additive/compatible/breaking/editorial), the typed manifest (`change-entry` records via lutaml-model) is emitted alongside `.changes.yaml` with a markdown changelog, and impact analysis walks `CorpusGraph#dependents_of` to report affected schemas and AP publications
- **`CorpusGraph`** — the declared-element graph of a whole schema collection: schemas, declared elements, USE/REFERENCE interface edges; the resolution substrate for `ClosureValidator` (and later change-impact/incremental builds)
- **`ClosureValidator`** — S1 referential closure: extracts every EXPRESS-internal reference (attribute domains, SELECT/aggregate branches, where-rule expressions, subtype constraints, supertype/subtype lists, rule applies-to, interfaces) and resolves it against a `CorpusGraph`; zero violations is the corpus well-formedness gate (`rake closure`)
- **`OwlProjection`** — S2 formal semantics: projects a parsed corpus into OWL/Turtle. Entities → `owl:Class`; `SUBTYPE OF` → `rdfs:subClassOf`; SELECT → `owl:unionOf`; enums → `owl:oneOf` named individuals; simple type aliases → `rdfs:Datatype`; explicit/derived/inverse attributes → object/datatype properties attached through named `owl:Restriction` nodes (cardinality from optionality and aggregate bounds); WHERE rules and DERIVE/INVERSE clauses → annotated (`rdfs:comment`) constraints. IRIs come from `Urn` (`<base>:tech:<schema>.<element>`), per-schema ontologies declare `owl:imports` for their `USE FROM`/`REFERENCE` targets, and the corpus ontology imports every schema. `#validate` checks materialization, property declarations, orphan classes, and superclass acyclicity. Output contains no blank nodes, so projections are deterministic and golden-comparable
- **`SchemaCache`** — content-addressed on-disk store for generated `.exp` output and parsed Expressir repositories. Keys compose source bytes with the Expressir version (plus Suma/Marshal versions for parsed entries), so a hit is equivalent to a fresh build. Enabled by `SUMA_SCHEMA_CACHE_DIR`; hit/miss counters expose parse reuse. **`NullCache`** is the disabled-mode null object
- **`BuildPlan`** — incremental-build decision: hashes every schema source, diffs against the persisted state, and expands changed schemas to their transitive dependents through `CorpusGraph`. State defaults to `plain_schemas/.suma-build-state.json`; `SchemaCollection#rebuild_targets` is the build-facing query
- **`WorkerPool`** — bounded worker pool for independent per-schema work. Schema export runs in the pool (`build --jobs N`); Metanorma document compilation stays sequential and composes with `StagedCollectionBuilder`'s process isolation
- **`UrnResolver`** — S4 dereferenceable identity: resolves `tech:` schema/element URNs from a manifest, `term:` concept URNs from Glossarist documents, and the dataset URN from `register.yaml`; emits canonical JSON plus a static HTML document per URN at a path derived from the URN itself. Every URN the register emits resolves against the artifact set
- **`Provenance`** — S5 build provenance: sha256 of every input and output (files or directory trees) plus Ruby/Expressir/Suma toolchain versions, written as canonical JSON by `build --provenance FILE`. `Provenance.verify` recomputes the digests independently; `build --sign minisign|sigstore` (with `--sign-key` where needed) optionally signs the manifest, and `bin/release_provenance` signs keylessly with cosign in the release workflow (`SUMA_PROVENANCE_SIGN`)
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
- Provenance on every concept: the source schema citation, the entity URN under `sourced_from`, and the owning edition/version
- Linked localizations: `--language-codes` emits additional `localizations` of the same managed concept (same stable UUID, per-language localized UUIDs); the text is the source-language content until translations are supplied

The `generate-register` command reads the same schema manifest and emits `register.yaml` with hierarchical sections:
- Top-level groups: Resources (133) before Application Modules (1123)
- Child sections use human-readable names from `SchemaNaming` (e.g. "Resource: Topology", "Module: Activity (ARM)")
- Parent group IDs are included in concept metadata so the concept-browser can filter by group

### External dependencies

- **expressir** — EXPRESS schema parsing and manifest handling
- **metanorma** — document compilation (`.adoc` → XML/HTML/PDF)
- **lutaml-model** — YAML/XML model serialization (used in `SiteConfig`, `CollectionConfig`)
- **glossarist** — term extraction output format
- **rdf / rdf-turtle** — OWL projection serialization (already required through glossarist; no direct gemspec entry)
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
