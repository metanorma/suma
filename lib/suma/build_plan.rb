# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

module Suma
  # Decides which schemas an incremental build must re-render.
  #
  # The state is a map of schema id → sha256 of its source. A schema is
  # changed when its digest differs from the previous build; rendering is
  # required for every changed schema plus all transitive dependents, because
  # a dependent's cross-references and rendered anchors may shift. The
  # dependents come from the corpus graph (S1), the same USE/REFERENCE edges
  # that drive change impact (S3).
  class BuildPlan
    # @param entries [Array<#id,#path>] schema manifest entries
    # @param graph [CorpusGraph]
    # @param previous_state [Hash{String=>String}] digest per schema id
    def initialize(entries:, graph:, previous_state: {})
      @entries = entries
      @graph = graph
      @previous_state = previous_state || {}
      @ids_by_key = entries.to_h { |entry| [entry.id.downcase, entry.id] }
    end

    # @return [Array<String>] declared ids whose source differs since the
    #   previous build (all ids on a first build)
    def changed
      current_state.reject do |id, digest|
        @previous_state[id] == digest
      end.keys
    end

    # @return [Array<String>] schemas to re-render: every changed schema plus
    #   its transitive dependents; empty when nothing changed
    def rebuild
      changed_ids = changed
      return [] if changed_ids.empty?

      expanded = changed_ids.flat_map do |id|
        [id] + @graph.dependents_of(id).map { |key| @ids_by_key[key] || key }
      end
      expanded.uniq
    end

    # @return [Hash{String=>String}] digest per schema id
    def current_state
      @current_state ||= @entries.to_h do |entry|
        [entry.id, Digest::SHA256.file(entry.path.to_s).hexdigest]
      end
    end

    # Persist the current state for the next incremental build.
    def self.write_state(path, state)
      FileUtils.mkdir_p(File.dirname(path))
      temp = "#{path}.#{Process.pid}.tmp"
      File.write(temp, JSON.pretty_generate(state))
      File.rename(temp, path)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end

    # @return [Hash{String=>String}] the previous state, empty when absent
    def self.read_state(path)
      return {} unless path && File.exist?(path)

      JSON.parse(File.read(path))
    end
  end
end
