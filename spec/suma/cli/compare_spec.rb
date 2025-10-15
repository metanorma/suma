# frozen_string_literal: true

require "suma/cli/compare"
require "suma/eengine/wrapper"
require "fileutils"
require "tmpdir"

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
        compare = described_class.new([], { version: "1.0" })
        compare.compare(trial_schema, reference_schema)

        # Verify changes.yaml was created
        expected_output = File.join(@tmpdir, "schema_v2.changes.yaml")
        expect(File.exist?(expected_output)).to be true

        # Verify content structure
        content = File.read(expected_output)
        expect(content).to include("schema:")
        expect(content).to include("schema_v2")
        expect(content).to include("editions:")
        expect(content).to include("version: '1.0'")
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

        compare = described_class.new([], { version: "1.0" })
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
          { version: "1.0", output: custom_output },
        )
        compare.compare(trial_schema, reference_schema)

        expect(File.exist?(custom_output)).to be true
      end

      it "updates existing changes.yaml with new version" do
        trial_schema = File.join(@tmpdir, "schema_v2.exp")
        reference_schema = File.join(@tmpdir, "schema_v1.exp")
        output_path = File.join(@tmpdir, "schema_v2.changes.yaml")
        FileUtils.cp(schema_v2, trial_schema)
        FileUtils.cp(schema_v1, reference_schema)

        # Create existing changes.yaml with version 1.0
        existing_content = <<~YAML
          ---
          schema:
            name: support_resource_schema
          editions:
          - version: '1.0'
            changes: []
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

        # Add version 2.0
        compare = described_class.new([], { version: "2.0" })
        compare.compare(trial_schema, reference_schema)

        content = File.read(output_path)
        expect(content).to include("version: '1.0'")
        expect(content).to include("version: '2.0'")
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
          { version: "1.0", mode: "module" },
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
