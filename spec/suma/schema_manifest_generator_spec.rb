# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::SchemaManifestGenerator do
  let(:work_dir) { Dir.mktmpdir("suma_gen_schemas") }
  let(:output_manifest) { File.join(work_dir, "schemas-site.yml") }

  after { FileUtils.rm_rf(work_dir) }

  # The nested `documents` manifest shape (metanorma 2.x collection
  # manifests): site -> collection -> document collections, each with a
  # sibling schemas.yaml. Fileref attachments in the document collection
  # must be ignored.
  before do
    FileUtils.mkdir_p(File.join(work_dir, %w[docs part41].join("/")))
    schemas_dir = File.join(work_dir, "schemas", "widgets")
    FileUtils.mkdir_p(schemas_dir)
    FileUtils.cp(
      File.expand_path("../fixtures/ap_publication/schemas/resources/" \
                       "widget_schema/widget_schema.exp", __dir__),
      File.join(schemas_dir, "widget_schema.exp"),
    )
    File.write(File.join(work_dir, "site.yml"), <<~YAML)
      ---
      metanorma:
        source:
          files:
            - collection.yml
    YAML
    File.write(File.join(work_dir, "collection.yml"), <<~YAML)
      ---
      directives:
      - documents-inline
      manifest:
        level: collection
        title: Site
        documents:
        - file: docs/part41/collection.yml
    YAML
    File.write(File.join(work_dir, "docs", "part41", "collection.yml"),
               <<~YAML)
                 ---
                 manifest:
                   level: collection
                   docref:
                   - level: document
                     docref:
                     - fileref: document.adoc
                       identifier: part41
                   - level: attachments
                     docref:
                     - fileref: ../../schemas/widgets/widget_schema.exp
                       identifier: widget_schema.exp
                       attachment: true
               YAML
    File.write(File.join(work_dir, "docs", "part41", "schemas.yaml"),
               <<~YAML)
                 ---
                 schemas:
                   widget_schema:
                     path: ../../schemas/widgets/widget_schema.exp
               YAML
  end

  it "resolves document collections declared with the documents key" do
    Dir.chdir(work_dir) do
      described_class.new("site.yml", output_manifest).generate
    end

    generated = YAML.safe_load_file(output_manifest)
    # /tmp is a symlink on macOS, so compare resolved paths, not text
    generated_path = File.expand_path(
      generated["schemas"]["widget_schema"]["path"], work_dir
    )

    aggregate_failures do
      expect(generated["schemas"].keys).to eq(["widget_schema"])
      expect(generated_path)
        .to eq(File.realpath(File.join(work_dir, "schemas", "widgets",
                                       "widget_schema.exp")))
    end
  end
end
