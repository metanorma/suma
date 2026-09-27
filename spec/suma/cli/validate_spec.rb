# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Suma::Cli::Validate do
  describe "#mappings" do
    let(:dir) { Dir.mktmpdir("suma-drift-cli") }
    let(:documents_path) { File.join(dir, "documents") }
    let(:baseline_path) do
      File.join(documents_path, "mapping-drift-baseline.yml")
    end
    let(:mapping_path) do
      File.join(documents_path, "modules", "m", "mapping.yaml")
    end

    def run_mappings(**opts)
      described_class.new([],
                          opts.transform_keys(&:to_s)).mappings(documents_path)
    end

    def ghost_mapping(ghost)
      <<~YAML
        ---
        ae:
        - entity: <<express:#{ghost}.thing,thing>>
          aimelt: <<express:m_arm.thing,thing>>
        sc: []
      YAML
    end

    def mapping_support?
      require "expressir/mapping"
      true
    rescue LoadError, NameError
      false
    end

    before do
      unless mapping_support?
        skip "requires expressir >= 2.4.20 (Expressir::Mapping)"
      end
      module_dir = File.join(documents_path, "modules", "m")
      FileUtils.mkdir_p(module_dir)
      File.write(File.join(module_dir, "arm.exp"),
                 "SCHEMA m_arm;\n" \
                 "ENTITY thing; a : STRING; END_ENTITY;\nEND_SCHEMA;\n")
      File.write(mapping_path, ghost_mapping("ghost"))
    end

    after { FileUtils.remove_entry(dir) }

    it "writes a baseline with --write-baseline" do
      run_mappings(write_baseline: true)
      expect(File).to exist(baseline_path)
    end

    it "passes when the drift matches the baseline" do
      run_mappings(write_baseline: true)
      expect { run_mappings }.to output(/0 new/).to_stdout
    end

    it "fails with module and location on new drift" do
      run_mappings(write_baseline: true)
      File.write(mapping_path, ghost_mapping("new_ghost"))

      expect { run_mappings }.to raise_error(
        Thor::Error, /new mapping drift.*modules\/m\/mapping\.yaml.*new_ghost/m
      )
    end
  end
end
