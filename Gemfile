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
gem "metanorma-iso"
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
