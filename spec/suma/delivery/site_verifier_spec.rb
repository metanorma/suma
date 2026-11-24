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

  # The page-shape checks (TRThurman, iso-10303#857): build-directory
  # leakage, listing completeness, own-remark publication, asciidoc
  # leakage, and the per-page inventory ratchet.
  describe "page-shape checks" do
    let(:remark) { "The demo schema defines the widget entity data type." }

    # A minimal attachment whose schema carries one own remark (an
    # untagged remark block before END_SCHEMA — expressir 2.4.80
    # attaches a placement-less comment to the FOLLOWING declaration,
    # so the schema-level channel needs the trailing placement).
    let(:demo_exp) do
      <<~EXP
        SCHEMA demo_schema;

          ENTITY widget;
            a : STRING;
          END_ENTITY;

        (*
        #{remark}
        *)
        END_SCHEMA;
      EXP
    end

    def build_shape_site(root, doc_html:, attachment: nil)
      write(root / "plain_schemas/demo_schema.exp", attachment) if attachment
      write(root / "schema_docs/doc_demo_schema.html", doc_html)
    end

    it "counts pages and occurrences of build-directory paths" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "ISO_A_2025/ISO_A_2025_index.html", <<~HTML)
          <html><body>
          <p>staged under /home/trth/work/site/plain_schemas</p>
          <a href="/Users/trth/notes.html">local note</a>
          </body></html>
        HTML
        write(root / "ISO_A_2025/other.html", "<html><body>clean</body></html>")

        report = verify(root).report

        expect(report["build_dir_pages"])
          .to eq(["ISO_A_2025/ISO_A_2025_index.html"])
        expect(report["build_dir_occurrences"]).to eq(2)
      end
    end

    it "honors configured forbidden path prefixes" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "page.html", "<html><body>/export/build/site</body></html>")

        configured = described_class
          .new(root, forbidden_path_prefixes: ["/export/"]).verify
        default = described_class.new(root).verify

        expect(configured.report["build_dir_occurrences"]).to eq(1)
        expect(default.report["build_dir_occurrences"]).to be_zero
      end
    end

    it "passes a schema-doc page whose listing closes inside a pre" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_shape_site(root, attachment: demo_exp, doc_html: <<~HTML)
          <html><body><pre>
          SCHEMA demo_schema;
          ENTITY widget; a : STRING; END_ENTITY;
          END_SCHEMA;
          </pre></body></html>
        HTML

        expect(verify(root).report["incomplete_listings"]).to be_empty
      end
    end

    it "flags a schema-doc page whose listing closed early" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_shape_site(root, attachment: demo_exp, doc_html: <<~HTML)
          <html><body><pre>
          SCHEMA demo_schema;
          ENTITY widget; a : STRING;
          </pre>
          <p>END_SCHEMA;</p>
          </body></html>
        HTML

        expect(verify(root).report["incomplete_listings"])
          .to eq(["schema_docs/doc_demo_schema.html"])
      end
    end

    it "scopes listing checks to schema-doc pages" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "ISO_A_2025/member_1.xml.1.html",
              "<html><body><p>END_SCHEMA;</p></body></html>")

        expect(verify(root).report["incomplete_listings"]).to be_empty
      end
    end

    it "passes a schema-doc page publishing its own remark" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_shape_site(root, attachment: demo_exp, doc_html: <<~HTML)
          <html><body><p>#{remark}</p>
          <pre>SCHEMA demo_schema; END_SCHEMA;</pre>
          </body></html>
        HTML

        expect(verify(root).report["missing_schema_remarks"]).to be_empty
      end
    end

    it "flags a schema with remarks whose page lacks them" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        page = "<html><body><pre>END_SCHEMA;</pre></body></html>"
        build_shape_site(root, attachment: demo_exp, doc_html: page)

        expect(verify(root).report["missing_schema_remarks"])
          .to eq(["demo_schema"])
      end
    end

    it "skips remark checks for schemas without an attachment" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_shape_site(root, doc_html: "<html><body>orphan</body></html>")

        expect(verify(root).report["missing_schema_remarks"]).to be_empty
      end
    end

    it "counts asciidoc macro text leakage" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "ISO_A_2025/ISO_A_2025_index.html", <<~HTML)
          <html><body>
          <p>image::fig1.png[] then link::other.html[]</p>
          <img src="fig2.png" title="image::fig2.png[]"/>
          </body></html>
        HTML

        report = verify(root).report

        # The title attribute is markup, not page text: two leaks only.
        expect(report["asciidoc_leak_pages"])
          .to eq(["ISO_A_2025/ISO_A_2025_index.html"])
        expect(report["asciidoc_leak_occurrences"]).to eq(2)
      end
    end

    it "does not count macros inside source listings" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "ISO_A_2025/ISO_A_2025_index.html", <<~HTML)
          <html><body>
          <pre class="sourcecode">(*"schema.ent.__figure"
          image::fig1.png[]
          ====)</pre>
          <p>image::fig2.png[]</p>
          </body></html>
        HTML

        report = verify(root).report

        # The source listing shows the annotated macros as written; only
        # the macro rendered outside the listing is leakage.
        expect(report["asciidoc_leak_occurrences"]).to eq(1)
      end
    end

    # The retired bare-"+" heuristic never produced a true positive on
    # real corpora: every hit was mathematical content — MathML renders
    # each operator as its own <mo> text node, HTML sub/sup notation
    # leaves "+" between elements, and hyperlinked code puts "+"
    # between linked operands (the 2026-11-22 SRL assemble: 354 phantom
    # leaks over 26 member section pages).
    it "does not count mathematical plus signs as leakage" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "ISO_A_2025/ISO_A_2025_index.html", <<~HTML)
          <html><body>
          <p><span><math><mstyle><mo>+</mo></mstyle></math></span></p>
          <p><i>C</i><sub><i>a</i></sub>+<i>C</i><sub><i>d</i></sub></p>
          <p><span>a</span> + <span>b</span></p>
          </body></html>
        HTML

        report = verify(root).report

        expect(report["asciidoc_leak_pages"]).to be_empty
        expect(report["asciidoc_leak_occurrences"]).to be_zero
      end
    end

    it "passes a clean page's asciidoc leakage check" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "page.html",
              '<html><body><img src="f.png"/>' \
              '<a href="o.html">o</a></body></html>')

        report = verify(root).report

        expect(report["asciidoc_leak_pages"]).to be_empty
        expect(report["asciidoc_leak_occurrences"]).to be_zero
      end
    end

    it "inventories per-page img and link counts" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "page.html", <<~HTML)
          <html><body>
          <img src="a.png"/><img src="b.png"/>
          <a href="other.html">one</a>
          <a href="#top">two</a>
          </body></html>
        HTML

        expect(verify(root).report["page_inventory"])
          .to eq("page.html" => { "imgs" => 2, "links" => 2 })
      end
    end
  end

  # The svgmap hotspot gate (TRThurman, iso-10303#875): anchor elements
  # inside SVG figures are the figure hotspots. A dead hotspot carries
  # live hover styling and a fragment whose anchor no longer exists, and
  # it passes both the plain link gate and the non-gating intra-fragment
  # census — the SRL shipped months of dead figure hotspots that way.
  describe "svg hotspot gate" do
    it "counts svg-internal anchors and reports unresolvable targets" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "fig.html", <<~HTML)
          <html><body>
          <h2 id="live-target">Live</h2>
          <svg xmlns="http://www.w3.org/2000/svg">
            <a href="#live-target"><rect id="hot-1"/></a>
            <a href="#dead-fragment"><rect id="hot-2"/></a>
            <a href="fig.html#live-target"><rect id="hot-3"/></a>
            <a href="missing.html"><rect id="hot-4"/></a>
          </svg>
          <a href="#dead-fragment">plain dead fragment, not a hotspot</a>
          </body></html>
        HTML

        report = verify(root).report

        expect(report["hotspots"]).to eq 4
        expect(report["hotspots_broken"]).to contain_exactly(
          { "source" => "fig.html", "href" => "#dead-fragment" },
          { "source" => "fig.html", "href" => "missing.html" },
        )
      end
    end

    it "gates the hotspot count and broken cap through expectations" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        write(root / "fig.html",
              '<html><body><svg><a href="#nope"><rect/></a></svg>' \
              "</body></html>")
        expectations = Suma::Delivery::Expectations.from_yaml(
          { "hotspots_min" => 5, "hotspots_broken_max" => 0 }.to_yaml,
        )
        report = verify(root).report
        violations = expectations.violations(report, []).join("; ")
        expect(violations).to include("hotspots_min")
        expect(violations).to include("hotspots_broken_max")
      end
    end
  end
end
