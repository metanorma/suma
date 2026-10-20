# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Validate referential closure of the fixture corpora"
task :closure do
  # `ruby` (Rake helper) rather than `bundle exec exe/suma`: the latter
  # does not resolve relative executables on Windows.
  ruby "exe/suma validate closure spec/fixtures/ap_publication/schemas.yaml"
end

task default: %i[spec rubocop closure]
