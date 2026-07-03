# TODO.update/05 — Extract Suma::NoteExtractor from TermExtractor

> Source: v0.3.0 audit follow-up. Pure refactor, no behavior change.
> Reduces TermExtractor from 25 private methods to a focused orchestrator.

## Current state

`lib/suma/term_extractor.rb` is 462 lines. Of those, ~210 are private
methods devoted to turning `entity.remarks` (Annotated EXPRESS prose)
into a clean array of `Glossarist::V3::DetailedDefinition` notes.

The note-processing pipeline (in invocation order):

```
get_entity_notes(entity, schema_domain, definitions)
  → trim_definition(entity.remarks)
      → apply_first_sentence_logic(paragraph)
      → extract_complete_list(paragraphs, start_index)
          → starts_with_list?(content)               # shared
          → is_list_continuation?(content)
      → express_reference_to_mention(combined)       # shared with descriptions
  → convert_express_xref(trimmed, schema_domain)     # separate gsub path
  → only_keep_first_sentence(notes)
      → should_preserve_complete_structure?(content)
          → starts_with_list?(content)               # shared
  → remove_see_content(notes)
  → remove_redundant_note(notes)                     # uses REDUNDANT_NOTE_REGEX
  → remove_invalid_references(notes)
  → compare_with_definitions(notes, definitions)     # final guard
```

The shared helpers (`starts_with_list?`, `express_reference_to_mention`)
bridge note extraction and definition generation. Everything else is
note-specific.

## Problem

TermExtractor mixes three concerns:

1. **Orchestration** — load manifest, walk schemas, build ManagedConcept.
2. **Definition generation** — `generate_entity_definition` (urn mentions
   composed from schema_type).
3. **Note extraction** — the 12-method pipeline above.

This makes TermExtractor hard to read, hard to test in isolation, and
hard to extend. Adding a new note-cleaning rule means editing a 462-line
file alongside unrelated orchestration code.

## Proposed split

```
Suma::TermExtractor (orchestrator)
  ├─ loads manifest
  ├─ builds ManagedConcept per entity
  ├─ delegates notes to NoteExtractor
  └─ delegates definitions to DefinitionBuilder (future)

Suma::NoteExtractor (prose-cleaning pipeline)
  ├─ input: entity.remarks, schema_domain, definition_for_comparison
  ├─ output: Array<Glossarist::V3::DetailedDefinition>
  └─ owns: trim_definition, apply_first_sentence_logic,
           extract_complete_list, is_list_continuation?,
           starts_with_list?, should_preserve_complete_structure?,
           only_keep_first_sentence, remove_see_content,
           remove_redundant_note, remove_invalid_references,
           compare_with_definitions, REDUNDANT_NOTE_REGEX

Suma::UrnMention (shared helper module)
  ├─ express_reference_to_mention(description)
  ├─ convert_express_xref(content, _schema_domain)
  └─ urn_mention, term_urn, express_entity_urn (already on TermExtractor
    via the Urn value object — relocate here)
```

`UrnMention` is a module so both `TermExtractor` (for definitions) and
`NoteExtractor` (for trim_definition's final stage and for
convert_express_xref) can include it without coupling to each other.

## Public API

```ruby
module Suma
  class NoteExtractor
    def initialize(urn_mention:)            # injected collaborator
      @urn_mention = urn_mention
    end

    # Returns [] if there are no usable notes after cleaning.
    def extract(remarks:, schema_domain:, definition:) ...
  end
end
```

TermExtractor wires it up:

```ruby
def build_localized_concept(...)
  ...
  notes = NoteExtractor.new(urn_mention: method(:urn_mention))
    .extract(remarks: entity.remarks,
             schema_domain: schema_domain,
             definition: data.definition.first&.content)
  data.notes = notes if notes&.any?
  ...
end
```

Or pass a small collaborator object instead of a method reference.

## Method inventory (what moves where)

### Moves to NoteExtractor (private)

- `REDUNDANT_NOTE_REGEX` constant
- `get_entity_notes` (becomes `extract`)
- `trim_definition`
- `apply_first_sentence_logic`
- `extract_complete_list`
- `is_list_continuation?`
- `starts_with_list?`
- `should_preserve_complete_structure?`
- `only_keep_first_sentence`
- `remove_see_content`
- `remove_redundant_note`
- `remove_invalid_references`
- `compare_with_definitions`

### Moves to UrnMention module

- `express_reference_to_mention`
- `convert_express_xref`

### Stays in TermExtractor

- Manifest loading (`get_exp_files`)
- `extract(exp_file)` orchestration
- `build_managed_concept_collection`
- `build_localized_concept`
- `get_entity_terms`
- `get_entity_definitions`
- `generate_entity_definition`
- `get_source_ref`, `get_section_ref`, `build_custom_locality`
- `schema_urn`, `term_urn`, `express_entity_urn`, `urn_mention`
- `extract_file_type`
- `get_domain`
- `entity_name_to_text`
- `output_data`

Net: TermExtractor shrinks from 462 → ~260 lines. NoteExtractor is
~200 lines of focused prose-cleaning.

## Files

- `lib/suma/note_extractor.rb` — new class.
- `lib/suma/urn_mention.rb` — new module (or `lib/suma/term_extractor/urn_mention.rb`
  if you prefer namespacing).
- `lib/suma/term_extractor.rb` — delete moved methods, wire up
  NoteExtractor and include UrnMention.
- `lib/suma.rb` — add autoloads for `NoteExtractor` and `UrnMention`.

## Spec requirements

This is a pure refactor — existing TermExtractor specs must pass
unchanged. The work is *adding* NoteExtractor specs that lock in the
cleaning rules.

### `spec/suma/note_extractor_spec.rb`

Cover every code path with real Annotated EXPRESS fixtures, not doubles:

**trim_definition input shapes:**
- Single-paragraph remark → first-sentence extraction
- Multi-paragraph remark, first paragraph ends with ":" + list body →
  list is preserved (first_paragraph + complete_list)
- Multi-paragraph remark, first paragraph ends with ":" + non-list body →
  first-sentence of first paragraph only
- Empty array → []
- nil → []
- String instead of Array → handled
- Remark with `//` Liquid-style comments → stripped
- Remark with `<<express:foo.bar>>` xref → converted to urn mention

**extract_complete_list:**
- List with continuation markers (`+`)
- List with `--` open/close delimiters
- List with nested indentation (`^\s{2,}`)
- List terminated by a non-list paragraph
- List at end of remarks (no terminator)

**only_keep_first_sentence:**
- Note with `:\n` followed by list → preserved (NOT first-sentence extracted)
- Note with period inside first paragraph → first-sentence logic applied
- nil content → preserved (no crash)

**remove filters:**
- `remove_see_content` strips ` (see ...)` phrases
- `remove_redundant_note` rejects "An X is a type of {{...}}" patterns
  unless they contain newlines
- `remove_invalid_references` rejects notes with `image::` or `<<...>>`
- `compare_with_definitions` returns [] when note matches the definition

**integration:**
- A real Annotated EXPRESS fixture (use `action_schema` from
  `spec/fixtures/extract_terms/resources/`) processed through NoteExtractor
  produces the same array of DetailedDefinition objects that the current
  TermExtractor produces. This is the regression guard.

### `spec/suma/urn_mention_spec.rb`

- `<<express:schema.entity>>` → `{{<urn>,entity}}`
- `<<express:schema.entity,display text>>` → `{{<urn>,display text}}`
- Multiple xrefs in one string → all converted
- Pathological inputs (the ones from the CodeQL ReDoS fix) → no
  catastrophic backtracking; fail fast

## Acceptance criteria

- `bundle exec rspec` passes unchanged (290 examples)
- New `spec/suma/note_extractor_spec.rb` covers every method
- New `spec/suma/urn_mention_spec.rb` covers the two mention helpers
- TermExtractor is < 300 lines
- No doubles in any new spec (per codebase rule)
- No `require_relative` in new files (autoload only)
- No `send` / `instance_variable_set` / `respond_to?` in new code
- `bundle exec rubocop` clean

## Out of scope

- Extracting `DefinitionBuilder` for `generate_entity_definition` —
  deferred to a follow-up. Definition generation has fewer methods and
  is less pressing.
- Refactoring `extract_file_type` (a string-classification helper) into
  the existing `ExpressSchema::Type` — the two classify different things
  (file suffix vs schema identity); don't conflate.

## Suggested PR scope

Single PR, three commits:

1. `refactor: extract Suma::UrnMention module for express-xref → urn-mention conversion`
2. `refactor: extract Suma::NoteExtractor from TermExtractor`
3. `test: add comprehensive NoteExtractor and UrnMention specs`

Three commits because (1) and (2) are sequential dependencies for (3),
and (1) is independently useful even if (2) is deferred.

## Risk

Behavior must be byte-identical. The integration test in
`spec/suma/note_extractor_spec.rb` (real action_schema fixture through
the pipeline) is the regression guard — without it, this refactor is
unsafe. Land specs in the same PR.
