# TODO.update/04 — Make Processor paths configurable

> Source: v0.3.0 audit follow-up. Backwards-compatible.

## Current state

`lib/suma/processor.rb` hardcodes four path literals:

```ruby
def initialize(metanorma_yaml_path:, schemas_all_path:, compile: true,
               output_directory: "_site")            # ← (1) "_site" is kwarg
  ...
end

def export_schema_config
  ...
  traverser.expand_schemas_only("schema_docs")       # ← (2) hardcoded
  ...
end

def compile_schema(schemas_all_path, collection_config)
  col = Suma::SchemaCollection.new(
    config_yaml: schemas_all_path,
    manifest: collection_config.manifest,
    output_path_docs: "schema_docs",                 # ← (3) hardcoded
    output_path_schemas: "plain_schemas",            # ← (4) hardcoded
  )
  ...
end

def build_collection(collection_config, output_directory)
  new_collection_config_path = "collection-output.yaml"   # ← (5) hardcoded
  ...
end
```

## Problem

Processor's signature claims `output_directory:` is configurable but
four other paths are not. A caller cannot redirect `schema_docs/`,
`plain_schemas/`, or the intermediate collection YAML without
subclassing. This bites:

- Tests that want to write to a tmpdir (Processor specs currently
  don't run end-to-end for this reason).
- Users who want to integrate suma into a different layout.
- The upcoming shared-cache work (PR #95), which benefits from a
  configurable intermediate path.

## Proposed change

Promote the literals to keyword arguments with the current values as
defaults. Backwards compatible.

```ruby
def initialize(metanorma_yaml_path:,
               schemas_all_path:,
               compile: true,
               output_directory: "_site",
               docs_subdir: "schema_docs",
               schemas_subdir: "plain_schemas",
               intermediate_collection_path: "collection-output.yaml")
  @metanorma_yaml_path = metanorma_yaml_path
  @schemas_all_path = schemas_all_path
  @compile_flag = compile
  @output_directory = output_directory
  @docs_subdir = docs_subdir
  @schemas_subdir = schemas_subdir
  @intermediate_collection_path = intermediate_collection_path
end
```

All internal methods reference the ivars; no literals remain inside
private methods.

## Files

- `lib/suma/processor.rb` — add kwargs, replace literals.
- `spec/suma/processor_spec.rb` — extend `#initialize` specs to cover
  the new kwargs (defaults preserve current behavior; explicit values
  are honored).

## Spec requirements

The current Processor spec only tests `#initialize`. Extend it:

- Defaults: all four new kwargs default to the literals above.
- Explicit values: passing `docs_subdir: "tmp/docs"` makes
  `compile_schema` write to `tmp/docs`.
- End-to-end smoke (optional, larger): construct Processor with
  tmpdir paths and a tiny fixture, run, assert outputs land where
  the kwargs say they do. This is a real integration test; the lack
  of one is why Processor paths got away with being hardcoded.

## Acceptance criteria

- `grep -n '"schema_docs"\|"plain_schemas"\|"collection-output.yaml"' lib/suma/processor.rb` returns nothing
- All existing specs pass unchanged (defaults preserve behavior)
- New `#initialize` specs cover the new kwargs
- `bundle exec rubocop` clean (watch AbcSize on `initialize` —
  currently fine, but adding 4 kwargs may push it; if so, extract
  to a `Suma::Processor::Paths` value object instead)

## Out of scope

- Suma::Paths value object — only if rubocop forces it.
- Removing `output_directory:` (still useful as a top-level concept).
- CLI surface (don't expose these as CLI flags unless asked).

## Suggested PR scope

Single commit:
`refactor: promote Processor's hardcoded paths to constructor kwargs`

If the kwargs make `initialize` too big, split into two commits:

1. Add a `Suma::Processor::Paths` struct
2. Use it in Processor

## Follow-up

If the kwargs count keeps growing, consider a `Suma::Config` value
object that consolidates env vars (`SUMA_DEBUG`, `SUMA_SCHEMA_CACHE_DIR`)
and CLI options. Out of scope here.
