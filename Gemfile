# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in suma.gemspec
gemspec

gem "canon"
# metanorma resolves from the gemspec constraint (~> 2.3) to the released gem.
# The staged-build render options (preserve_unresolved:/artifact_store_dir:/
# reinflate:, metanorma#578) landed in metanorma 2.5.0, now on rubygems, so the
# former feature-branch override (feature/collection-incremental-resumable) is
# dropped: CI builds against a stable released metanorma, not a floating branch.
# Flavor gem needed to compile the dummy-collection integration fixture
# (spec/fixtures/dummy_collection, suma#107).
# metanorma-iso releases (<= 3.5.0) require "pubid-iso"/"pubid-cen"/
# "pubid-iec" (pubid 1.15 split gems) that do not exist on the relaton-3
# chain, and whose lib/pubid/*.rb collide with the pubid 2 monolith's.
# The pubid-2 migration is on metanorma-iso main; it needs the unreleased
# metanorma-standoc "Standoc::Document" split, so pin that from main too.
# Flip both to released gems once metanorma-iso releases the migration.
gem "metanorma-iso", github: "metanorma/metanorma-iso", branch: "main"
gem "metanorma-standoc", github: "metanorma/metanorma-standoc", branch: "main"
# metanorma#607: Collection#bibitem must drop localized <edition> variants
# (metanorma-iso main emits them) before the relaton parse.
gem "metanorma", github: "metanorma/metanorma",
    branch: "fix/collection-bibdata-localized-edition"
# iso/standoc main also use unreleased metanorma-document 0.5.x model
# classes (e.g. Components::Inline::TermrefElement).
gem "metanorma-document", github: "metanorma/metanorma-document", branch: "main"
# gem "metanorma-plugin-lutaml", github: "metanorma/metanorma-plugin-lutaml", branch: "main"
# gem "metanorma-standoc", github: "metanorma/metanorma-standoc", branch: "main"
# gem "expressir", github: "lutaml/expressir", branch: "main"
gem "nokogiri"
gem "openssl", "~> 3.0"
gem "rake"
gem "rspec"
gem "rubocop"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "expressir", "2.4.27"
# isodoc 3.7.3 `require`s "sassc-embedded" while rendering HTML but does
# not declare it.
gem "sassc-embedded", "~> 1.0"
# relaton-render's floor (>= 2.0.0.pre.alpha.6) admits the stale June
# 2.2.0.pre prerelease, which predates lutaml-model 0.8.78's strict
# collection checks (duplicate <edition> raise). 2.1.9 is the current
# lutaml-model-0.8 line.
gem "relaton-bib", "2.1.9"

