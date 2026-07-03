# TODO.update/06 — Collapse the double-Thor CLI pattern into Thor subcommands

> Source: v0.3.0 audit follow-up. Large; separate PR.
> This is the structural fix for the class of bug that PR #96 patched
> symptomatically.

## Current state

`lib/suma/cli.rb` defines `Suma::Cli::Core < Thor` with one `desc`/`def`
pair per subcommand. Each `def` body delegates to a separate Thor
subclass by calling `Cli::<Name>.start(args)`:

```ruby
module Suma
  module Cli
    class Core < Thor
      desc "extract-terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
           "Extract EXPRESS entity concepts ..."
      option :urn, ...        # ← PR #96 added: options must be declared here too
      option :language_code, ...
      def extract_terms(*args)
        Cli::ExtractTerms.start(args)   # ← inner Thor reparses ARGV
      end

      # ... 8 more delegations
    end
  end
end
```

Each inner class (`Cli::ExtractTerms < Thor`, `Cli::Compare < Thor`, …)
lives in its own file under `lib/suma/cli/`.

## Problem

This is the "double-Thor" pattern. Thor parses ARGV twice:

1. `Core` parses it first (with `check_unknown_options!` enabled via
   `ThorExt::Start`).
2. If `Core` accepts the parse, it delegates to the inner Thor, which
   reparses the same ARGV with its own option declarations.

Any option declared only on the inner Thor is unknown to Core and gets
rejected. PR #96 fixed this for `extract-terms` and `generate-register`
by duplicating the option declarations onto `Core`. The fix is
symptomatic — every other inner Thor command with options has the same
bug latent.

The PR #96 description itself flags this:

> Out of scope (follow-up): the other inner-Thor commands (`build`,
> `reformat`, `convert-jsdai`, `export`, `compare`) likely have the same
> bug if they take options. Worth auditing in a separate PR if any of
> them have inner-class options.

This is that follow-up.

## Proposed change

Use Thor's built-in `subcommand` feature. `Core` becomes a thin
register of subcommands; each `Cli::<Name>` keeps its `desc`/`option`
declarations exactly once.

```ruby
module Suma
  module Cli
    class Core < Thor
      # ThorExt::Start enhancements remain at this level
      def self.start(args = ARGV, ...)
        super
      end

      desc "version", "Print suma version"
      def version
        say Suma::VERSION
      end

      # Every former delegation becomes a one-line subcommand registration.
      subcommand "build",            Suma::Cli::Build
      subcommand "convert-jsdai",    Suma::Cli::ConvertJsdai
      subcommand "extract-terms",    Suma::Cli::ExtractTerms
      subcommand "generate-register", Suma::Cli::GenerateRegister
      subcommand "generate-schemas", Suma::Cli::GenerateSchemas
      subcommand "reformat",         Suma::Cli::Reformat
      subcommand "compare",          Suma::Cli::Compare
      subcommand "export",           Suma::Cli::Export
      subcommand "validate",         Suma::Cli::Validate
      subcommand "check-svg-quality", Suma::Cli::CheckSvgQuality
      subcommand "expressir",        Suma::Cli::Expressir
    end
  end
end
```

Each `Cli::<Name>` is already a Thor subclass. With subcommand
registration, the only thing that changes is:

1. Each inner class promotes its command from a method to the class
   default command (so `suma extract-terms foo bar` invokes the inner
   class's default command).
2. Drop the wrapper `def extract_terms(*args); Cli::ExtractTerms.start(args); end`
3. Drop the duplicated `option` declarations on Core (PR #96's patch).
4. Drop the inner-class `.start` calls.

Two equivalent ways to make the inner class invokable as a subcommand:

### Option A: `default_command` (one command per inner class)

Each inner class declares its single command and sets it as default:

```ruby
class ExtractTerms < Thor
  default_command :extract_terms

  desc "extract_terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
       "Extract EXPRESS entity concepts ..."
  option :urn, ...
  option :language_code, ...
  def extract_terms(...)
    Suma::TermExtractor.new(...).call
  end
end
```

Now `suma extract-terms foo bar --urn x` invokes
`Cli::ExtractTerms#extract_terms` directly.

### Option B: namespace + invoke

Thor supports namespaced subcommands with multiple commands per
subcommand. Heavier; not needed here.

**Recommendation: Option A** — every inner class already has exactly one
command. `default_command` is the minimal change.

## Migration plan

One PR, file-by-file. Order matters because Core must keep working at
every commit.

1. Convert each inner class to use `default_command`. Pure addition
   (existing `.start` API still works). One commit per class or all
   at once.
2. Update `lib/suma/cli.rb` (Core) — replace each `desc/def` pair with
   `subcommand "name", Cli::Name`. Drop duplicated `option` declarations.
3. Update `lib/suma/cli/core.rb` if it has any dispatch logic (it
   doesn't currently — it's mostly `ThorExt::Start`).
4. Update `exe/suma` if it does anything beyond `Suma::Cli::Core.start`.

## Files

- `lib/suma/cli.rb` — rewrite Core as a subcommand register.
- `lib/suma/cli/build.rb`, `compare.rb`, `convert_jsdai.rb`,
  `export.rb`, `extract_terms.rb`, `generate_register.rb`,
  `generate_schemas.rb`, `reformat.rb`, `validate.rb`,
  `validate_links.rb`, `check_svg_quality.rb` — add `default_command`,
  remove any PR #96-era workaround code.
- `lib/suma/cli/core.rb` — verify `ThorExt::Start` integration still
  works with subcommands.
- `exe/suma` — likely unchanged.

## Spec requirements

There is currently no end-to-end CLI spec. The existing CLI specs
invoke `described_class.new.invoke(:command, args, opts)`, which
exercises the inner classes directly. After the refactor, those specs
continue to work.

Add a new `spec/suma/cli/core_spec.rb` that exercises Core as a user
would, to lock in the subcommand dispatch contract:

- `suma extract-terms --urn x foo bar` parses correctly through Core
- `suma extract-terms --unknown-option` rejects the option at Core
  (because the option isn't declared on ExtractTerms, not because of
  duplicated declarations on Core)
- `suma help extract-terms` shows the option (it doesn't need to be
  re-declared on Core)
- Every subcommand listed in `suma help` is invokable

Use a real `Cli::Core.new.invoke(:extract_terms, ...)` — no doubles.

## Acceptance criteria

- `lib/suma/cli.rb` (Core) has zero `option` declarations and zero
  `def <command>(*args); ... end` delegations
- Every inner class has `default_command :<name>` and its own `option`s
- `suma extract-terms --urn x ...`, `suma generate-register --urn ...`,
  and every other documented CLI invocation works as documented
- `suma help` lists every subcommand
- `suma help <subcommand>` shows the options for that subcommand
- All existing specs pass
- New `spec/suma/cli/core_spec.rb` covers the dispatch contract

## Risks

- **Help output changes shape.** Thor's `subcommand` produces slightly
  different help text than flat `desc`. Anyone parsing `suma help`
  output (CI scripts?) needs to verify.
- **Option precedence.** Global options on Core (`--help`) might
  interact with subcommand options. Verify in specs.
- **`ThorExt::Start` integration.** The custom `-h`/`--help` handling
  in ThorExt was written for the flat pattern; verify it still fires
  for subcommands.

## Out of scope

- Splitting `Suma::Cli::Validate` (currently a dispatcher to
  `ValidateLinks`) into a proper subcommand namespace — this resolves
  naturally once Validate is registered as a subcommand.
- Removing inner Thor classes that don't add value (some are thin
  shells around a service) — separate cleanup.

## Suggested PR scope

Single PR, three commits:

1. `refactor: declare default_command on each Cli::<Name> subclass`
2. `refactor: replace Cli::Core delegations with Thor subcommands`
3. `test: add spec/suma/cli/core_spec.rb for subcommand dispatch`

(1) and (2) are sequenced. (3) lands with (2) ideally; if review
requests it, (3) can precede (2) as a "characterisation test"
capturing current behavior, then (2) verifies it still passes.

## Pre-reqs

- PR #96 (which patched the symptomatic option-duplication) is already
  merged. This refactor subsumes PR #96's patches — they'll be removed.
- No dependency on TODO.update/03, 04, or 05.

## Post-merge

The "double-Thor" bug class is gone. New CLI commands declare their
options once. Adding a command becomes:

```ruby
class Cli::NewThing < Thor
  default_command :new_thing
  desc "new_thing PATH", "Do the thing"
  option :flag, type: :boolean
  def new_thing(path)
    Suma::NewThingService.new(path, flag: options[:flag]).call
  end
end
```

```ruby
# lib/suma/cli.rb — one line:
subcommand "new-thing", Suma::Cli::NewThing
```

No duplication, no second parse, no chance of Core rejecting options
it doesn't know about.
