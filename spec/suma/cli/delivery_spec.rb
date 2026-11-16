# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "tmpdir"

# The verify command surface: summary line format, gate exit codes
# (broken links, expectations, inventory ratchet), and the
# machine-readable report contents.
RSpec.describe Suma::Cli::Delivery do
  def write(path, content)
    path.parent.mkpath
    path.write(content)
  end

  def build_clean_site(root)
    write(root / "a.html",
          '<html><body><a href="b.html#x">b</a>' \
          '<img src="a.png"/></body></html>')
    write(root / "b.html", '<html><body><h1 id="x">X</h1></body></html>')
  end

  def build_broken_site(root)
    write(root / "a.html",
          '<html><body><a href="missing.html">m</a></body></html>')
    write(root / "b.html", "<html><body>nothing links here</body></html>")
  end

  def verify(dir, **opts)
    out = StringIO.new
    saved = Suma::Utils.output
    Suma::Utils.output = out
    begin
      cmd = described_class.new([], opts.transform_keys(&:to_s))
      cmd.verify(dir.to_s)
    ensure
      Suma::Utils.output = saved
    end
    out.string
  end

  it "appends the page-shape census to the site summary line" do
    Dir.mktmpdir do |dir|
      build_clean_site(Pathname.new(dir))

      expect(verify(dir)).to include(
        "site: sections=0 indexes=0 attachments=0 schema_docs=0; " \
        "missing-express pages=0; build-dir=0 listings=0 remarks=0 leaks=0",
      )
    end
  end

  it "fails with a non-zero gate on broken links" do
    Dir.mktmpdir do |dir|
      build_broken_site(Pathname.new(dir))

      expect { verify(dir) }
        .to raise_error(RuntimeError, /broken links found \(1\)/)
    end
  end

  context "with expectations" do
    it "passes when the census meets every cap" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_broken_site(root)
        manifest = root / "expectations.yaml"
        manifest.write("broken_links_max: 1\nasciidoc_leaks_max: 0\n")

        expect(verify(root, expectations: manifest.to_s))
          .to include("build-dir=0 listings=0 remarks=0 leaks=0")
      end
    end

    it "fails listing every violated threshold" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_broken_site(root)
        write(root / "leaky.html",
              "<html><body><p>image::f.png[]</p></body></html>")
        manifest = root / "expectations.yaml"
        manifest.write("broken_links_max: 0\nasciidoc_leaks_max: 0\n")

        expect { verify(root, expectations: manifest.to_s) }
          .to raise_error(
            RuntimeError,
            /expectations violated.*broken_links_max.*asciidoc_leaks_max/m,
          )
      end
    end
  end

  context "with an inventory baseline" do
    it "passes when no page's counts moved" do
      Dir.mktmpdir do |dir|
        build_clean_site(Pathname.new(dir))
        baseline = File.join(dir, "baseline.yml")
        File.write(baseline, <<~YAML)
          a.html:
            imgs: 1
            links: 1
          b.html:
            imgs: 0
            links: 0
        YAML

        expect(verify(dir, inventory_baseline: baseline)).to be_a(String)
      end
    end

    it "fails listing every page whose counts changed" do
      Dir.mktmpdir do |dir|
        build_clean_site(Pathname.new(dir))
        baseline = File.join(dir, "baseline.yml")
        File.write(baseline, <<~YAML)
          a.html:
            imgs: 1
            links: 2
        YAML

        expect { verify(dir, inventory_baseline: baseline) }
          .to raise_error(
            RuntimeError, /page inventory changed: a\.html \(links 2->1\)/
          )
      end
    end

    it "fires the ratchet even when the link gate is green" do
      Dir.mktmpdir do |dir|
        build_clean_site(Pathname.new(dir))
        baseline = File.join(dir, "baseline.yml")
        File.write(baseline, "gone.html:\n  imgs: 3\n  links: 3\n")

        expect { verify(dir, inventory_baseline: baseline) }
          .to raise_error(RuntimeError, /gone\.html/)
      end
    end
  end

  it "emits the page-shape census in the machine-readable report" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      build_clean_site(root)
      out_path = root / "report.json"

      verify(root, out: out_path.to_s)
      report = JSON.parse(File.read(out_path))

      expect(report["page_inventory"])
        .to eq("a.html" => { "imgs" => 1, "links" => 1 },
               "b.html" => { "imgs" => 0, "links" => 0 })
      expect(report["build_dir_occurrences"]).to eq(0)
      expect(report["incomplete_listings"]).to eq([])
      expect(report["missing_schema_remarks"]).to eq([])
      expect(report["asciidoc_leak_occurrences"]).to eq(0)
    end
  end
end
