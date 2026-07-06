# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in suma.gemspec
gemspec

gem "canon"
# Staged build (suma#94) needs the preserve_unresolved: / artifact_store_dir: /
# reinflate: render options from metanorma#578 (metanorma 2.5.0). Point at the
# feature branch until it is released; drop this once 2.5.0 is on rubygems.
gem "metanorma", github: "metanorma/metanorma",
                 branch: "feature/collection-incremental-resumable"
# gem "metanorma-plugin-lutaml", github: "metanorma/metanorma-plugin-lutaml", branch: "main"
# gem "metanorma-standoc", github: "metanorma/metanorma-standoc", branch: "main"
gem "nokogiri"
gem "openssl", "~> 3.0"
gem "rake"
gem "rspec"
gem "rubocop"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
