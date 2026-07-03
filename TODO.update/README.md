# TODO.update

Next-round refactor plans, sequenced by risk and dependency. Each file
is sized to one focused PR.

| # | File | Scope | Size | Risk |
|---|------|-------|------|------|
| 03 | [drop-redundant-schema-name-to-docs](03-drop-redundant-schema-name-to-docs.md) | Remove duplicate `@schema_name_to_docs` hash in SchemaCollection | XS | None |
| 04 | [processor-configurable-paths](04-processor-configurable-paths.md) | Promote Processor's hardcoded paths to constructor kwargs | S | None (backwards-compatible) |
| 05 | [extract-note-extractor](05-extract-note-extractor.md) | Split prose-cleaning logic out of TermExtractor into NoteExtractor + UrnMention | M | Behavioral — needs spec coverage landed in same PR |
| 06 | [collapse-double-thor](06-collapse-double-thor.md) | Replace double-Thor CLI dispatch with Thor `subcommand` | M | Help-output shape change; verify ThorExt integration |

The numbering starts at 03 to follow on from the v0.3.0 audit's
"Suggested next actions" list (where 1 and 2 were contributor-PR actions
on #95 and #35, not local refactors).

## Dependency graph

```
03 → standalone (5-line change, do first as a warmup)
04 → standalone (backwards-compatible)
05 → standalone (own specs land in same PR)
06 → standalone (post-PR-96 follow-up)
```

None of these block each other. They can land in parallel if reviewers
are available, or serially in numerical order.

## Recommended execution order

1. **03** first — trivially safe, takes 5 minutes, removes a real
   correctness footgun (the duplicate hash can drift).
2. **04** next — small, backwards-compatible, enables Processor
   end-to-end specs which the codebase currently lacks.
3. **05** is the highest-payoff refactor: TermExtractor is the most
   complex class in the codebase and the prose-cleaning pipeline is
   the bulk of that complexity. Specs locked in first via integration
   test against `action_schema` fixture.
4. **06** last — touches every CLI file and changes `suma help` output.
   Worth its own PR with a characterisation test.

## What's not here

These items were considered and deferred:

- **Suma::Config value object** — only worth doing if configuration
  surface grows. Right now env vars (SUMA_DEBUG, SUMA_SCHEMA_CACHE_DIR
  post-#95) and constructor kwargs are manageable.
- **SchemaCompiler dependency injection of Metanorma::Compile** — the
  current direct invocation is fine; DI would add complexity without
  enabling tests we don't already have.
- **Parallel SchemaCollection#compile** — Ractor/thread pool. The
  stale `feature/performance-next` branch tried this and reverted;
  needs a separate investigation before committing.
- **Suma::NoteExtractor → further split into SentenceExtractor +
  ListExtractor + ReferenceFilter** — over-engineering for the current
  complexity. One NoteExtractor class is the right size.

## PR conventions

Each plan follows:

- **Current state** — what the code looks like today
- **Problem** — why it needs to change, with concrete examples
- **Proposed change** — what the new shape is
- **Files** — exhaustive list of touched files
- **Spec requirements** — what specs must exist (new or preserved)
- **Acceptance criteria** — grep-able checks
- **Out of scope** — what explicitly not to do
- **Suggested PR scope** — commit structure

If a plan is missing any of these, that's a bug in the plan.

## Code-style invariants (apply to every PR in this directory)

- Ruby `autoload` only; no `require_relative` in `lib/`
- No `send` to call private methods
- No `instance_variable_set` / `instance_variable_get`
- No `respond_to?` for type checks
- No doubles in specs; use real instances, `Struct`, or `Class.new`
- `Utils.log` writes to `$stderr`; debug level gated by `SUMA_DEBUG`
- Every new public method gets a spec; every behavioral edge case is covered
- `frozen_string_literal: true` in every file
- Rubocop clean (refresh `.rubocop_todo.yml` via
  `rubocop -A --auto-gen-config` before merge)
