# TODO.update/03 — Drop redundant `@schema_name_to_docs` hash in SchemaCollection

> Source: v0.3.0 audit follow-up. Small, safe, no behavior change.

## Current state

`lib/suma/schema_collection.rb:13-14, 25, 72-74` keeps two parallel hashes that
store the same `id → compiler` mapping:

```ruby
def initialize(...)
  @schemas = {}
  @docs = {}
  @schema_name_to_docs = {}   # ← duplicate of @docs
end

def doc_from_schema_name(schema_name)
  @schema_name_to_docs[schema_name]
end

def process_schema(...)
  @docs[express.id] = compiler
  @schemas[express.id] = express
  @schema_name_to_docs[express.id] = compiler   # ← duplicate write
end
```

## Problem

Two homes for one piece of state violates single source of truth. Every
write site must remember to update both. Every reader must know which
hash to consult. They can drift.

External callers of `doc_from_schema_name`: none. Verified with
`grep -rn 'doc_from_schema_name' lib/ spec/ exe/` — only the class
itself and a single spec that exercises the reader.

## Proposed change

Single source of truth: `@docs` only.

```ruby
def initialize(...)
  @schemas = {}
  @docs = {}
  ...
end

def doc_from_schema_name(schema_name)
  @docs[schema_name]
end

def process_schema(...)
  @docs[express.id] = compiler
  @schemas[express.id] = express
end
```

Net: −4 lines, one less ivar, one less write per schema.

## Files

- `lib/suma/schema_collection.rb` — remove `@schema_name_to_docs`, repoint
  `doc_from_schema_name` to `@docs`.

## Spec impact

None. `doc_from_schema_name` continues to work identically. Existing
specs (when added) cover it through the public API.

## Acceptance criteria

- `grep -n 'schema_name_to_docs' lib/suma/` returns nothing
- `bundle exec rspec` passes unchanged
- `bundle exec rubocop` clean
- No public API change

## Out of scope

- Renaming `@docs` to something more descriptive (`@compilers_by_id`)
  — cosmetic, can do separately.
- Removing `doc_from_schema_name` if no external caller — keep for now
  as a documented public reader.

## Suggested PR scope

Single commit:
`refactor: drop redundant @schema_name_to_docs hash in SchemaCollection`
