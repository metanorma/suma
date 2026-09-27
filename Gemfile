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
# Expressir >= 2.4.4 passes the lutaml-model `serialize:` mapping
# kwarg, which needs lutaml-model >= 0.8.50, which needs rubyzip ~> 3,
# which needs glossarist >= 2.14, which needs relaton ~> 3.0.0.pre.alpha
# — a chain no RELEASED metanorma accepts. Left unpinned, the resolver
# lands on expressir 2.4.5 (whose gemspec under-declares its
# lutaml-model floor) + lutaml-model 0.8.29, a pair that crashes at
# load with `unknown keyword: :serialize`. Pin the last released
# expressir that works on this chain; lift once a released metanorma
# accepts relaton 3.
gem "expressir", "2.4.3"

# Metanorma 2.5.5 was released referencing Metanorma::Core::Flavors,
# which only exists in unreleased metanorma-core; its gemspec
# under-declares the metanorma-core floor, so fresh resolves crash at
# Metanorma::Collection.parse. Stay on the last consistent release
# until metanorma-core ships.
gem "metanorma", "< 2.5.5"

# metanorma-plugin-lutaml 0.7.52+ calls Expressir::Express::LazyRepository
# (expressir >= 2.4.20) but its gemspec still allows expressir >= 2.3.5,
# breaking builds on the pinned expressir line above.
gem "metanorma-plugin-lutaml", "< 0.7.52"
