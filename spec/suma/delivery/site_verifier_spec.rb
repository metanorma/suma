# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# The site-wide link verification contract: cross-file hrefs must
# resolve, fragments must resolve against the target's anchors, .err.html
# files are exempt, intra-file fragment breakage is reported without
# failing, and bare-integer hrefs (unbound imagemap hotspots) count as
# broken links — dead whatever the key form.
RSpec.describe Suma::Delivery::SiteVerifier do
  def write(path, content)
    path.parent.mkpath
    path.write(content)
  end

  def build_site(root)
    write(root / "ISO_A_2025/ISO_A_2025_index.html", <<~HTML)
      <html><body id="top">
      <a href="ISO_A_2025_section_0.html#intro">Section zero</a>
      <a href="ISO_A_2025_section_0.html#missing-anchor">Broken frag</a>
      <a href="#top">To top</a>
      <a href="#nowhere-here">Broken intra</a>
      <a href="missing.html">Broken file</a>
      <a href="https://example.com">External</a>
      <a href="42">Imagemap</a>
      </body></html>
    HTML
    write(root / "ISO_A_2025/ISO_A_2025_section_0.html", <<~HTML)
      <html><body><h2 id="intro">Intro</h2></body></html>
    HTML
    write(root / "ISO_A_2025/document.err.html", <<~HTML)
      <html><body><a href="definitely-missing.html">err link</a></body></html>
    HTML
  end

  def verify(root)
    described_class.new(root).verify
  end

  it "resolves working links and fragments, and flags the broken ones" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      build_site(root)

      report = verify(root).report

      # The scheme href is excluded from the total; the bare-integer
      # href ("42", an unbound imagemap hotspot) is counted and broken —
      # a link to a nonexistent file is dead whatever the key form.
      expect(report["total_links"]).to eq(4)
      expect(report["resolved_links"]).to eq(2)
      expect(report["broken_links"].map { |b| b["href"] })
        .to contain_exactly("missing.html", "42")

      expect(report["total_fragments"]).to eq(2)
      expect(report["resolved_fragments"]).to eq(1)
      expect(report["broken_fragments"].first["fragment"]).to eq("missing-anchor")

      # All links stay within ISO_A_2025/: no directory crossings.
      expect(report["cross_document_links"]).to eq(0)

      # .err.html links are exempt from the walk entirely.
      expect(report["total_links"]).to eq(4)
    end
  end

  it "reports intra-file fragment breakage without failing the gate" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      build_site(root)

      result = verify(root)

      expect(result.report["total_intra_fragments"]).to eq(2)
      expect(result.report["resolved_intra_fragments"]).to eq(1)
      expect(result.report["broken_intra_fragments"].first["fragment"])
        .to eq("nowhere-here")
      # The gate counts only cross-file breaks: the broken file link
      # plus the bare-integer hotspot href.
      expect(result.broken_count).to eq(3)
    end
  end

  it "passes a fully-resolving site" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      write(root / "a.html", '<html><body><a href="b.html#x">b</a></body></html>')
      write(root / "b.html", '<html><body><h1 id="x">X</h1></body></html>')

      expect(verify(root).broken_count).to be_zero
    end
  end

  it "inventories the site shape and scans for missing-express pages" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      write(root / "ISO_A_2025/ISO_A_2025_index.html",
            "<html><body>fine</body></html>")
      write(root / "ISO_A_2025/member_a.xml.1.html",
            '<html><body><a href="12">unbound</a></body></html>')
      write(root / "ISO_A_2025/member_b.xml.2.err.html",
            "<html><body>Missing:express:secret</body></html>")
      write(root / "ISO_A_2025/member_c.xml.3.html",
            "<html><body>Missing:express:basis_schema.x</body></html>")
      write(root / "plain_schemas/a.exp", "(* schema *)")
      Dir.mkdir(root / "schema_docs")
      FileUtils.touch(root / "schema_docs/a.adoc")

      report = verify(root).report

      # The .err.html page is exempt from the walk and the inventory.
      expect(report["inventory"]).to eq(
        "sections" => 2, "index_pages" => 1,
        "schema_attachments" => 1, "schema_docs" => 1
      )
      expect(report["missing_express_pages"])
        .to eq(["ISO_A_2025/member_c.xml.3.html"])
    end
  end

  # The err.html census rides in the report the expectations gate reads
  # (metanorma/suma#203): .err.html pages are exempt from the link walk
  # but counted for diagnostic rows.
  it "censuses the site's err.html diagnostic rows" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      write(root / "ISO_A_2025/document.err.html", <<~HTML)
        <html><body><h1>document.err.html errors</h1>
        <ul></ul>
        <h2 id="Referencing">Referencing</h2>
        <table border="1"><tbody>
        <tr class="severity1"><td>1</td><th><code>_a</code></th><td>ISO_56</td>
        <td>cross-reference target a is undefined</td><td><pre>x</pre></td><td>1</td></tr>
        <tr class="severity1"><td>2</td><th><code>_b</code></th><td>ISO_56</td>
        <td>cross-reference target b is undefined</td><td><pre>y</pre></td><td>1</td></tr>
        </tbody></table>
        </body></html>
      HTML

      expect(verify(root).report["diagnostics"])
        .to eq("Referencing" => { "ISO_56" => 2 })
    end
  end
end
