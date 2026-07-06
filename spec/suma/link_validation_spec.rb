# frozen_string_literal: true

require "suma/link_validation"
require "suma/schema_index"
require "expressir"
require "tmpdir"
require "fileutils"

RSpec.describe Suma::LinkValidation do
  let(:fixtures_root) do
    File.expand_path("../fixtures/link_validation", __dir__)
  end

  let(:schemas_file) { File.join(fixtures_root, "schemas.yml") }

  let(:documents_dir) do
    Dir.mktmpdir("suma_link_validation_docs")
  end

  let(:output_file) { File.join(documents_dir, "out.txt") }

  after do
    FileUtils.rm_rf(documents_dir)
  end

  def write_adoc(dir, name, body)
    path = File.join(dir, name)
    File.write(path, body)
    path
  end

  describe "#call" do
    it "returns a Result with file counts and an unresolved list" do
      result = described_class.new(
        schemas_file: schemas_file,
        documents_path: documents_dir,
        output_file: output_file,
        progress: silent_progress,
      ).call

      expect(result).to be_a(Suma::LinkValidation::Result)
      expect(result.exp_count).to eq(1)
      expect(result.adoc_count).to eq(0)
      expect(result.total_links).to eq(0)
    end

    it "reports unresolved links with file, line, and reason" do
      adoc = write_adoc(documents_dir, "bad.adoc",
                        "intro\n<<express:missing_schema>>\n")
      result = described_class.new(
        schemas_file: schemas_file,
        documents_path: documents_dir,
        output_file: output_file,
        progress: silent_progress,
      ).call

      expect(result.unresolved.length).to eq(1)
      issue = result.unresolved.first
      expect(issue.file).to eq(adoc)
      expect(issue.line).to eq(2)
      expect(issue.link).to eq("missing_schema")
      expect(issue.reason).to include("Schema 'missing_schema' not found")
    end

    it "resolves links when the target schema exists" do
      write_adoc(documents_dir, "ok.adoc",
                 "<<express:test_schema>>\n")
      result = described_class.new(
        schemas_file: schemas_file,
        documents_path: documents_dir,
        output_file: output_file,
        progress: silent_progress,
      ).call

      expect(result.unresolved).to be_empty
      expect(result.success?).to be(true)
    end

    it "writes the summary file when an output path is given" do
      write_adoc(documents_dir, "ok.adoc", "<<express:test_schema>>\n")
      described_class.new(
        schemas_file: schemas_file,
        documents_path: documents_dir,
        output_file: output_file,
        progress: silent_progress,
      ).call

      expect(File.exist?(output_file)).to be(true)
      contents = File.read(output_file)
      expect(contents).to include("Validation complete")
      expect(contents).to include("All links resolved")
    end

    it "raises Suma::Error when the schemas file cannot be loaded" do
      bogus = File.join(documents_dir, "bogus.yml")
      # Write malformed YAML — Expressir should refuse to parse it.
      File.write(bogus, "this: : :\n  - [unbalanced\n")
      expect do
        described_class.new(
          schemas_file: bogus,
          documents_path: documents_dir,
          output_file: output_file,
        ).call
      end.to raise_error(Suma::Error, /Error loading schemas file/)
    end

    it "invokes the progress adapter once per file and once per schema" do
      progress = recording_progress
      write_adoc(documents_dir, "a.adoc", "<<express:test_schema>>\n")
      write_adoc(documents_dir, "b.adoc", "<<express:test_schema>>\n")

      described_class.new(
        schemas_file: schemas_file,
        documents_path: documents_dir,
        output_file: nil,
        progress: progress,
      ).call

      # The adapter should have received at least one #start call per
      # phase (file scan, schema load) and one #increment per file
      # processed.
      expect(progress.starts.length).to be >= 2
      expect(progress.increments).to be >= 2
    end
  end

  describe ".generate_summary" do
    it "formats the all-resolved case" do
      result = Suma::LinkValidation::Result.new(
        adoc_count: 2, exp_count: 1, total_links: 5, unresolved: [],
      )
      summary = described_class.generate_summary(result)
      expect(summary).to include("Checked 5 links")
      expect(summary).to include("✅ All links resolved successfully!")
    end

    it "formats unresolved issues with file:line, link, and reason" do
      unresolved = [
        Suma::LinkValidationResult.new(
          file: "foo.adoc", line: 7, link: "missing",
          reason: "Schema 'missing' not found"
        ),
      ]
      result = Suma::LinkValidation::Result.new(
        adoc_count: 1, exp_count: 1, total_links: 3, unresolved: unresolved,
      )
      summary = described_class.generate_summary(result)
      expect(summary).to include("Found 1 unresolved links")
      expect(summary).to include("foo.adoc:7")
      expect(summary).to include("<<express:missing>>")
      expect(summary).to include("Schema 'missing' not found")
    end
  end

  describe "Result" do
    it "is keyword-initialised" do
      result = Suma::LinkValidation::Result.new(
        adoc_count: 1, exp_count: 0, total_links: 0, unresolved: [],
      )
      expect(result.adoc_count).to eq(1)
      expect(result.exp_count).to eq(0)
      expect(result.total_links).to eq(0)
      expect(result.unresolved).to eq([])
    end

    it "reports success? when unresolved is empty" do
      result = Suma::LinkValidation::Result.new(
        adoc_count: 0, exp_count: 0, total_links: 0, unresolved: [],
      )
      expect(result.success?).to be(true)
    end
  end

  describe "NullProgress" do
    it "responds to start and increment without error" do
      progress = Suma::LinkValidation::NullProgress.new
      expect { progress.start("title", 5) }.not_to raise_error
      expect { progress.increment }.not_to raise_error
    end
  end

  describe "EXPRESS_LINK_PATTERN" do
    it "captures the link target without the display text" do
      match = "<<express:action_schema.action_directive_relationship>>"
        .match(described_class::EXPRESS_LINK_PATTERN)
      expect(match[1]).to eq("action_schema.action_directive_relationship")
    end

    it "captures the link target when a display text is present" do
      match = "<<express:action_schema,name>>"
        .match(described_class::EXPRESS_LINK_PATTERN)
      expect(match[1]).to eq("action_schema")
    end
  end

  def silent_progress
    Suma::LinkValidation::NullProgress.new
  end

  def recording_progress
    Class.new do
      attr_reader :starts, :increments

      def initialize
        @starts = []
        @increments = 0
      end

      def start(title, total)
        @starts << [title, total]
      end

      def increment
        @increments += 1
      end
    end.new
  end
end
