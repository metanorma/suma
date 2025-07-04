# frozen_string_literal: true

require_relative "lib/suma/version"

Gem::Specification.new do |spec| # rubocop:disable Metrics/BlockLength
  spec.name = "suma"
  spec.version = Suma::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Utility for SUMA " \
                 "(STEP Unified Model-Based Standards Architecture)"
  spec.description = <<~DESCRIPTION
    Utility for SUMA (STEP Unified Model-Based Standards Architecture)
  DESCRIPTION

  spec.homepage = "https://github.com/metanorma/suma"
  spec.license = "BSD-2-Clause"

  spec.bindir = "bin"
  spec.require_paths = ["lib"]
  spec.files = `git ls-files`.split("\n")
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "expressir", "~> 2.1"
  spec.add_dependency "glossarist", "~> 2.3.7"
  spec.add_dependency "lutaml-model", "~> 0.7"
  spec.add_dependency "metanorma-cli"
  spec.add_dependency "plurimath"
  spec.add_dependency "ruby-progressbar"
  spec.add_dependency "terminal-table", "~> 3.0"
  spec.add_dependency "thor", ">= 0.20"
  spec.metadata["rubygems_mfa_required"] = "true"
end
