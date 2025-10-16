# frozen_string_literal: true

require "suma/cli/compare"
require "suma/eengine/wrapper"
require "fileutils"
require "tmpdir"
require "yaml"

RSpec.describe Suma::Cli::Compare do
  let(:fixtures_dir) { File.expand_path("../../fixtures/compare", __dir__) }
  let(:schema_v1) { File.join(fixtures_dir, "schema_v1.exp") }
  let(:schema_v2) { File.join(fixtures_dir, "schema_v2.exp") }
  let(:expected_xml) { File.join(fixtures_dir, "expected_comparison.xml") }

  around do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      example.run
    ensure
      @tmpdir = nil
    end
  end

  describe "#compare" do
    context "when eengine is not available" do
      before do
        allow(Suma::Eengine::Wrapper).to receive(:available?).and_return(false)
      end

      it "exits with error message" do
        compare = described_class.new
        expect { compare.compare(schema_v2, schema_v1) }
          .to raise_error(SystemExit)
      end
    end

    context "when trial schema does not exist" do
      before do
        allow(Suma::Eengine::Wrapper).to receive(:available?).and_return(true)
      end

      it "exits with error message" do
        compare = described_class.new
        expect { compare.compare("nonexistent.exp", schema_v1) }
          .to raise_error(SystemExit)
      end
    end

    context "when reference schema does not exist" do
      before do
        allow(Suma::Eengine::Wrapper).to receive(:available?).and_return(true)
      end

      it "exits with error message" do
        compare = described_class.new
        expect { compare.compare(schema_v2, "nonexistent.exp") }
          .to raise_error(SystemExit)
      end
    end

    context "when eengine is available and schemas exist" do
      before do
        allow(Suma::Eengine::Wrapper).to receive_messages(available?: true,
                                                          version: "5.2.7")
      end

      it "compares schemas and generates changes.yaml" do
        # Copy schemas to tmpdir to simulate real workflow
        trial_schema = File.join(@tmpdir, "schema_v2.exp")
        reference_schema = File.join(@tmpdir, "schema_v1.exp")
        FileUtils.cp(schema_v2, trial_schema)
        FileUtils.cp(schema_v1, reference_schema)

        # Mock eengine comparison
        xml_output = File.join(@tmpdir, "comparison.xml")
        FileUtils.cp(expected_xml, xml_output)

        allow(Suma::Eengine::Wrapper).to receive(:compare)
          .and_return({
                        success: true,
                        xml_path: xml_output,
                        has_changes: true,
                        output: "Comparing TYPE text\nWriting \"#{xml_output}\"",
                      })

        # Run compare command
        compare = described_class.new([], { version: "1" })
        compare.compare(trial_schema, reference_schema)

        # Verify changes.yaml was created
        expected_output = File.join(@tmpdir, "schema_v2.changes.yaml")
        expect(File.exist?(expected_output)).to be true

        # Verify YAML structure matches schema_changes.yaml schema
        yaml_data = YAML.load_file(expected_output)

        # Validate required top-level fields
        expect(yaml_data).to have_key("schema")
        expect(yaml_data).to have_key("versions")
        expect(yaml_data.keys.sort).to eq(%w[schema versions])

        # Validate schema field
        expect(yaml_data["schema"]).to be_a(String)
        expect(yaml_data["schema"]).to eq("schema_v2")

        # Validate versions array
        expect(yaml_data["versions"]).to be_an(Array)
        expect(yaml_data["versions"]).not_to be_empty

        # Validate version structure
        version_entry = yaml_data["versions"].first
        expect(version_entry).to have_key("version")
        expect(version_entry["version"]).to be_an(Integer)
        expect(version_entry["version"]).to eq(1)

        # Validate optional fields if present
        if version_entry.key?("description")
          expect(version_entry["description"]).to be_a(String)
        end

        # Validate change arrays if present
        %w[additions modifications removals].each do |change_type|
          next unless version_entry.key?(change_type)

          expect(version_entry[change_type]).to be_an(Array)

          version_entry[change_type].each do |item|
            # Required fields
            expect(item).to have_key("type")
            expect(item).to have_key("name")
            expect(item["type"]).to be_a(String)
            expect(item["name"]).to be_a(String)

            # Validate type enum
            valid_types = %w[
              ENTITY TYPE FUNCTION RULE PROCEDURE
              CONSTANT REFERENCE_FROM USE_FROM SUBTYPE_CONSTRAINT
            ]
            expect(valid_types).to include(item["type"])

            # Optional fields
            if item.key?("description")
              expect(item["description"]).to be_an(Array)
              item["description"].each do |desc|
                expect(desc).to be_a(String)
              end
            end

            if item.key?("interfaced_items")
              expect(item["interfaced_items"]).to be_an(Array)
              item["interfaced_items"].each do |interfaced_item|
                expect(interfaced_item).to be_a(String)
              end
            end
          end
        end

        # Validate no additional properties at version level
        valid_version_keys = %w[
          version description additions modifications removals
        ]
        version_entry.keys.each do |key|
          expect(valid_version_keys).to include(key)
        end
      end

      it "handles no changes detected" do
        trial_schema = File.join(@tmpdir, "schema.exp")
        reference_schema = File.join(@tmpdir, "schema_old.exp")
        FileUtils.cp(schema_v1, trial_schema)
        FileUtils.cp(schema_v1, reference_schema)

        allow(Suma::Eengine::Wrapper).to receive(:compare)
          .and_return({
                        success: true,
                        xml_path: nil,
                        has_changes: false,
                        output: "No changes detected",
                      })

        compare = described_class.new([], { version: 1 })
        expect { compare.compare(trial_schema, reference_schema) }
          .not_to raise_error

        # Verify no changes.yaml was created
        expected_output = File.join(@tmpdir, "schema.changes.yaml")
        expect(File.exist?(expected_output)).to be false
      end

      it "uses custom output path when specified" do
        trial_schema = File.join(@tmpdir, "schema_v2.exp")
        reference_schema = File.join(@tmpdir, "schema_v1.exp")
        custom_output = File.join(@tmpdir, "custom_changes.yaml")
        FileUtils.cp(schema_v2, trial_schema)
        FileUtils.cp(schema_v1, reference_schema)

        xml_output = File.join(@tmpdir, "comparison.xml")
        FileUtils.cp(expected_xml, xml_output)

        allow(Suma::Eengine::Wrapper).to receive(:compare)
          .and_return({
                        success: true,
                        xml_path: xml_output,
                        has_changes: true,
                        output: "Writing \"#{xml_output}\"",
                      })

        compare = described_class.new(
          [],
          { version: "1", output: custom_output },
        )
        compare.compare(trial_schema, reference_schema)

        expect(File.exist?(custom_output)).to be true

        # Verify the custom output follows schema structure
        yaml_data = YAML.load_file(custom_output)
        expect(yaml_data).to have_key("schema")
        expect(yaml_data).to have_key("versions")
        expect(yaml_data["versions"].first["version"]).to be_an(Integer)
      end

      it "updates existing changes.yaml with new version" do
        trial_schema = File.join(@tmpdir, "schema_v2.exp")
        reference_schema = File.join(@tmpdir, "schema_v1.exp")
        output_path = File.join(@tmpdir, "schema_v2.changes.yaml")
        FileUtils.cp(schema_v2, trial_schema)
        FileUtils.cp(schema_v1, reference_schema)

        # Create existing changes.yaml with version 1
        existing_content = <<~YAML
          ---
          schema: schema_v2
          versions:
          - version: 1
            modifications:
            - type: TYPE
              name: existing_type
              description:
              - "Existing modification"
        YAML
        File.write(output_path, existing_content)

        xml_output = File.join(@tmpdir, "comparison.xml")
        FileUtils.cp(expected_xml, xml_output)

        allow(Suma::Eengine::Wrapper).to receive(:compare)
          .and_return({
                        success: true,
                        xml_path: xml_output,
                        has_changes: true,
                        output: "Writing \"#{xml_output}\"",
                      })

        # Add version 2
        compare = described_class.new([], { version: "2" })
        compare.compare(trial_schema, reference_schema)

        # Verify YAML structure is maintained
        yaml_data = YAML.load_file(output_path)

        expect(yaml_data["versions"]).to be_an(Array)
        expect(yaml_data["versions"].length).to eq(2)

        # Verify both versions exist and are integers
        versions = yaml_data["versions"].map { |v| v["version"] }
        expect(versions).to contain_exactly(1, 2)

        # Verify structure compliance for both versions
        yaml_data["versions"].each do |version_entry|
          expect(version_entry["version"]).to be_an(Integer)

          %w[additions modifications removals].each do |change_type|
            next unless version_entry.key?(change_type)

            version_entry[change_type].each do |item|
              expect(item).to have_key("type")
              expect(item).to have_key("name")
            end
          end
        end
      end

      it "passes mode option to eengine" do
        trial_schema = File.join(@tmpdir, "schema_v2.exp")
        reference_schema = File.join(@tmpdir, "schema_v1.exp")
        FileUtils.cp(schema_v2, trial_schema)
        FileUtils.cp(schema_v1, reference_schema)

        xml_output = File.join(@tmpdir, "comparison.xml")
        FileUtils.cp(expected_xml, xml_output)

        expect(Suma::Eengine::Wrapper).to receive(:compare)
          .with(
            trial_schema,
            reference_schema,
            hash_including(mode: "module"),
          )
          .and_return({
                        success: true,
                        xml_path: xml_output,
                        has_changes: true,
                        output: "Writing \"#{xml_output}\"",
                      })

        compare = described_class.new(
          [],
          { version: "1", mode: "module" },
        )
        compare.compare(trial_schema, reference_schema)
      end
    end

    describe "repository root detection" do
      it "detects git repository root" do
        # Create a mock git repo structure
        git_dir = File.join(@tmpdir, ".git")
        FileUtils.mkdir_p(git_dir)

        schemas_dir = File.join(@tmpdir, "schemas", "resources")
        FileUtils.mkdir_p(schemas_dir)

        schema = File.join(schemas_dir, "schema.exp")
        FileUtils.touch(schema)

        compare = described_class.new
        root = compare.send(:detect_repo_root, schema)

        expect(root).to eq(@tmpdir)
      end

      it "falls back to schema directory when no git repo found" do
        schemas_dir = File.join(@tmpdir, "schemas")
        FileUtils.mkdir_p(schemas_dir)

        schema = File.join(schemas_dir, "schema.exp")
        FileUtils.touch(schema)

        compare = described_class.new
        root = compare.send(:detect_repo_root, schema)

        expect(root).to eq(schemas_dir)
      end
    end

    describe "schema name extraction" do
      it "extracts schema name without version suffix" do
        compare = described_class.new
        name = compare.send(:extract_schema_name, "/path/to/schema_1.exp")
        expect(name).to eq("schema")
      end

      it "extracts schema name without version suffix for _2" do
        compare = described_class.new
        name = compare.send(:extract_schema_name, "/path/to/schema_2.exp")
        expect(name).to eq("schema")
      end

      it "keeps schema name without version" do
        compare = described_class.new
        name = compare.send(:extract_schema_name, "/path/to/my_schema.exp")
        expect(name).to eq("my_schema")
      end
    end
  end
end
