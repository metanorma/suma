# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Suma::MappingDrift do
  let(:dir) { Dir.mktmpdir("suma-drift") }
  let(:documents_path) { File.join(dir, "documents") }
  let(:baseline_path) { File.join(dir, "baseline.yml") }
  let(:drift) { described_class.new(documents_path) }

  def write_module(name, mapping_body)
    module_dir = File.join(documents_path, "modules", name)
    FileUtils.mkdir_p(module_dir)
    File.write(File.join(module_dir, "arm.exp"),
               "SCHEMA #{name}_arm;\n" \
               "ENTITY thing; a : STRING; END_ENTITY;\nEND_SCHEMA;\n")
    File.write(File.join(module_dir, "mim.exp"),
               "SCHEMA #{name}_mim;\nUSE FROM #{name}_arm (thing);\n" \
               "ENTITY thing; a : STRING; END_ENTITY;\nEND_SCHEMA;\n")
    File.write(File.join(module_dir, "mapping.yaml"), mapping_body)
  end

  def clean_mapping(name)
    <<~YAML
      ---
      ae:
      - entity: <<express:#{name}_arm.thing,thing>>
        aimelt: <<express:#{name}_mim.thing,thing>>
      sc: []
    YAML
  end

  def unknown_link_mapping(name, ghost)
    <<~YAML
      ---
      ae:
      - entity: <<express:#{name}_arm.thing,thing>>
        aimelt: <<express:#{ghost}.thing,thing>>
      sc: []
    YAML
  end

  def ghost_refpath_mapping
    <<~YAML
      ---
      ae:
      - entity: <<express:drift_mod_arm.thing,thing>>
        aimelt: <<express:ghost_schema.thing,thing>>
        refpath:
          content: |-
            ghost_type <= thing
      sc: []
    YAML
  end

  def assertion_mapping
    <<~YAML
      ---
      ae:
      - entity: <<express:clean_mod_arm.thing,thing>>
        aimelt: <<express:clean_mod_mim.thing,thing>>
        aa:
        - attribute: a
          assertion_to: <<express:new_ghost.thing,thing>>
      sc: []
    YAML
  end

  def ghost_refpath_keys
    [
      "modules/drift_mod/mapping.yaml|unknown_link|ghost_schema.thing",
      "modules/drift_mod/mapping.yaml|refpath|<<express:drift_mod_arm.thing," \
      "thing>> [step 0]: unknown type 'ghost_type'",
    ]
  end

  before do
    unless mapping_support?
      skip "requires expressir >= 2.4.20 (Expressir::Mapping)"
    end

    FileUtils.mkdir_p(documents_path)
  end

  after { FileUtils.remove_entry(dir) }

  def mapping_support?
    require "expressir/mapping"
    true
  rescue LoadError, NameError
    false
  end

  it "finds no drift when every link resolves" do
    write_module("clean_mod", clean_mapping("clean_mod"))
    expect(drift.scan.entries).to be_empty
  end

  it "reports unknown links and refpath issues per module" do
    write_module("drift_mod", ghost_refpath_mapping)
    expect(drift.scan.keys).to match_array(ghost_refpath_keys)
  end

  it "survives an unreadable mapping as a load entry" do
    write_module("broken_mod", "\t{- not yaml")
    prefix = "modules/broken_mod/mapping.yaml|load|"
    expect(drift.scan.keys.first).to start_with(prefix)
  end

  it "round-trips a baseline through YAML" do
    write_module("drift_mod", unknown_link_mapping("drift_mod", "ghost_schema"))
    File.write(baseline_path, drift.scan.to_yaml)

    expect(drift.check(baseline_path).last).to be_empty
  end

  def clean_mapping_path
    File.join(documents_path, "modules", "clean_mod", "mapping.yaml")
  end

  def new_drift_key
    "modules/clean_mod/mapping.yaml|unknown_link|new_ghost.thing"
  end

  it "flags only NEW drift against the baseline" do
    write_module("clean_mod", clean_mapping("clean_mod"))
    write_module("drift_mod", unknown_link_mapping("drift_mod", "ghost_schema"))
    File.write(baseline_path, drift.scan.to_yaml)

    File.write(clean_mapping_path, assertion_mapping)
    expect(drift.check(baseline_path).last).to contain_exactly(new_drift_key)
  end
end
