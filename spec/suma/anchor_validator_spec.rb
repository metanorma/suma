# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::AnchorValidator do
  subject(:validator) { described_class.new(directory) }

  let(:directory) { Dir.mktmpdir("suma_anchors") }

  after { FileUtils.rm_rf(directory) }

  def write_doc(id, adoc:, html:)
    doc_dir = File.join(directory, id)
    FileUtils.mkdir_p(doc_dir)
    File.write(File.join(doc_dir, "doc_#{id}.adoc"), adoc)
    File.write(File.join(doc_dir, "doc_#{id}.html"), html)
  end

  it "accepts a document whose xrefs and hrefs all resolve" do
    write_doc(
      "ok_schema",
      adoc: <<~ADOC,
        == ok_schema
        See <<ok_schema.widget,a widget>> and <<widget.name,the name>>.
      ADOC
      html: <<~HTML,
        <h2 id="ok_schema">ok_schema</h2>
        <a id="ok_schema.widget"></a><a id="widget.name"></a>
        <a href="#ok_schema.widget">widget</a>
      HTML
    )

    expect(validator.validate).to eq([])
  end

  it "rejects an xref whose target has no anchor in the rendered HTML" do
    write_doc(
      "dead_schema",
      adoc: "See <<dead_schema.missing,missing>>.\n",
      html: "<h2 id=\"dead_schema\">dead_schema</h2>\n",
    )
    violation = validator.validate.first

    aggregate_failures do
      expect(violation.link).to eq("dead_schema.missing")
      expect(violation.reason).to include("no anchor")
    end
  end

  it "rejects an in-page href pointing at no id" do
    write_doc(
      "href_schema",
      adoc: "== href_schema\n",
      html: "<a href=\"#nowhere\">gone</a>\n",
    )
    violation = validator.validate.first

    aggregate_failures do
      expect(violation.link).to eq("#nowhere")
      expect(violation.reason).to include("in-page link")
    end
  end

  it "skips cross-document xrefs" do
    write_doc(
      "cross_schema",
      adoc: "See <<other.adoc#other_schema.entity,other>>.\n",
      html: "<h2 id=\"cross_schema\">cross_schema</h2>\n",
    )

    expect(validator.validate).to eq([])
  end

  it "reports a doc whose HTML was not rendered" do
    FileUtils.mkdir_p(File.join(directory, "bare_schema"))
    File.write(File.join(directory, "bare_schema", "doc_bare_schema.adoc"),
               "== bare_schema\n")
    violation = validator.validate.first

    aggregate_failures do
      expect(violation.link).to end_with("doc_bare_schema.html")
      expect(violation.reason).to include("no rendered HTML")
    end
  end

  it "walks nested document trees" do
    write_doc(
      "nested_schema",
      adoc: "See <<nested_schema.entity,entity>>.\n",
      html: "<a id=\"nested_schema.entity\"></a>\n",
    )

    expect(validator.validate).to eq([])
  end
end
