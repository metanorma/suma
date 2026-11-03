# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# The site-wide link verification contract, pinned against
# site_manifest.py verify_links: cross-file hrefs must resolve, fragments
# must resolve against the target's anchors, .err.html files are exempt,
# and intra-file fragment breakage is reported without failing.
RSpec.describe Suma::Srl::SiteVerifier do
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

      # The scheme and bare-integer hrefs are excluded from the total,
      # matching the Python scanner; .err.html files from the walk entirely.
      expect(report["total_links"]).to eq(3)
      expect(report["resolved_links"]).to eq(2)
      expect(report["broken_links"].map { |b| b["href"] })
        .to contain_exactly("missing.html")

      expect(report["total_fragments"]).to eq(2)
      expect(report["resolved_fragments"]).to eq(1)
      expect(report["broken_fragments"].first["fragment"]).to eq("missing-anchor")

      # All links stay within ISO_A_2025/: no directory crossings.
      expect(report["cross_document_links"]).to eq(0)

      # .err.html links are exempt from the walk entirely.
      expect(report["total_links"]).to eq(3)
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
      # The gate counts only cross-file breaks.
      expect(result.broken_count).to eq(2)
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
end
