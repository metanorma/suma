# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# The frame-navigation delivery postprocess contract, pinned against
# suma2srl.py: index surgery, frame onclick wiring, target="info", and
# the section-page sidebar suppression.
RSpec.describe Suma::Srl::FrameNav do
  def write(path, content)
    path.parent.mkpath
    path.write(content)
  end

  def build_site(root)
    write(root / "index.html", <<~HTML)
      <html><head><title>Site</title></head><body>
      <nav>
        <p>STEP Resources Library (SRL)</p>
        <ul>
          <li>Document<ul>
            <li><div><a href="ISO_A_2025/ISO_A_2025_index.html">Part A</a></div></li>
            <li><div><a href="ISO_B_2025.pdf">Part B single</a></div></li>
          </ul></li>
          <li>Attachments<ul>
            <li><a href="plain_schemas/x/x.exp">x.exp</a></li>
          </ul></li>
        </ul>
        <h2>Attachments</h2>
        <ul><li><a href="logo.svg">logo</a></li></ul>
      </nav>
      </body></html>
    HTML
    write(root / "ISO_A_2025/ISO_A_2025_index.html", <<~HTML)
      <html><head></head><body>
      <a href="ISO_A_2025_section_0.html">Foreword</a>
      <a href="ISO_A_2025_section_1.html">Scope</a>
      </body></html>
    HTML
    write(root / "ISO_A_2025/ISO_A_2025_section_0.html", <<~HTML)
      <html><head><title>A0</title></head><body><p>Section zero</p></body></html>
    HTML
  end

  it "wires the frame navigation into the top-level index" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      build_site(root)

      described_class.new(root).process

      index = (root / "index.html").read
      expect(index).to include(
        "parent.index.location.replace('ISO_A_2025/ISO_A_2025_index.html');" \
        "parent.info.location='ISO_A_2025/ISO_A_2025_section_0.html';",
      )
      expect(index).to include("parent.info.location='ISO_B_2025.pdf'")
      expect(index).to include(described_class::FRAMESET_JS)
      expect(index).not_to include("Attachments")
      # The Document/Attachments wrappers collapse; the attachment
      # subtree dies with the decomposed element (A/B-caught against
      # the Python pipeline on the real reference site).
      expect(index).not_to include("x.exp")
      expect(index).to include("Part A")
      expect(index).not_to include("STEP Resources Library")
    end
  end

  it "adds target=info to document index links" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      build_site(root)

      described_class.new(root).process

      doc_index = (root / "ISO_A_2025/ISO_A_2025_index.html").read
      expect(doc_index.scan('target="info"').size).to eq(2)
    end
  end

  it "injects the sidebar suppression into section pages, idempotently" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      build_site(root)
      frame_nav = described_class.new(root)

      frame_nav.process
      frame_nav.process

      section = (root / "ISO_A_2025/ISO_A_2025_section_0.html").read
      expect(section.scan("nav{display:none !important}").size).to eq(1)
      expect(section).to include('content:"DRAFT"')
      expect(section.index(described_class::CSS_OVERRIDE))
        .to be < section.index("</head>")
    end
  end
end
