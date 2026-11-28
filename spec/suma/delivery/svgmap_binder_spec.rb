# frozen_string_literal: true

require "spec_helper"
require "suma/delivery/svgmap_binder"
require "tmpdir"

# The fixtures are per-example file trees; each example pairs the bind
# counts with the rewritten hrefs it produced.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

RSpec.describe Suma::Delivery::SvgmapBinder do
  let(:docs_dir) { Pathname.new(Dir.mktmpdir("suma_svgmap_bind")) }

  after do
    FileUtils.rm_rf(docs_dir)
  end

  # A schema page carrying one EXPRESS-G figure per anchor id; each
  # figure's svg holds the given integer-href hotspots alongside a
  # bound-in-render fragment.
  def schema_page(schema, figures = {}, entities: %w[identifier label])
    anchors = figures.map do |anchor, ordinals|
      spots = ordinals.map { |n| %(<a href="#{n}"><text>#{n}</text></a>) }
      %(<figure id="#{anchor}"><svg><g>#{spots.join}</g>
        <a href="##{schema}"><text>self</text></a></svg></figure>)
    end
    ids = [schema, *entities.map { |e| "#{schema}.#{e}" }].uniq
    id_tags = ids.map { |i| %(<p id="#{i}">x</p>) }.join
    <<~HTML
      <!DOCTYPE html>
      <html><body>
      #{id_tags}
      #{anchors.join("\n")}
      </body></html>
    HTML
  end

  # One svgmap per figure anchor; targets are ordinal => element children
  # (eref bibitemids stay unbound, link targets are already resolved).
  def schema_presentation(_schema, svgmaps)
    blocks = svgmaps.map do |anchor, targets|
      t = targets.map do |ordinal, child|
        %(<target href="#{ordinal}">#{child}</target>)
      end
      head = %(<svgmap><figure anchor="#{anchor}"/>)
      %(#{head}<image src="d.svg"/>#{t.join}</svgmap>)
    end
    <<~XML
      <?xml version="1.0"?>
      <document>#{blocks.join}</document>
    XML
  end

  def eref(bibitemid)
    %(<eref bibitemid="#{bibitemid}"/>)
  end

  def link_to(schema)
    %(<link target="../#{schema}/doc_#{schema}.html"/>)
  end

  def write_tree(pages:, presentations:)
    pages.each do |schema, body|
      dir = docs_dir.join(schema)
      dir.mkpath
      dir.join("doc_#{schema}.html").write(body)
    end
    presentations.each do |schema, body|
      docs_dir.join(schema, "doc_#{schema}.presentation.xml").write(body)
    end
  end

  def hrefs_of(page_html, figure_anchor)
    doc = Leptris::XML.parse_html(docs_dir.join(page_html).read)
    fig = doc.xpath("//*[@id = '#{figure_anchor}']").first
    fig.xpath(".//*[local-name() = 'svg']//*[local-name() = 'a']")
      .map { |a| a["href"].to_s }
  end

  def stamped_of(page_html)
    doc = Leptris::XML.parse_html(docs_dir.join(page_html).read)
    doc.xpath("//*[@data-svgmap-bibitemid]")
      .to_h { |a| [a["href"].to_s, a["data-svgmap-bibitemid"]] }
  end

  it "binds cross-schema, same-page and stamped targets, and leaves " \
     "the rest" do
    write_tree(
      pages: {
        "support_resource_schema" =>
          schema_page("support_resource_schema"),
        "basic_attribute_schema" => schema_page(
          "basic_attribute_schema",
          {
            "basic_attribute_schema_expg1" => %w[1 2 3],
            "basic_attribute_schema_expg2" => %w[1],
          },
          entities: %w[identifier label id_attribute_select],
        ),
      },
      presentations: {
        "basic_attribute_schema" => schema_presentation(
          "basic_attribute_schema",
          "basic_attribute_schema_expg1" => {
            "1" => eref("express_support_resource_schema.identifier"),
            "2" => link_to("support_resource_schema"),
            "3" => eref("express_basic_attribute_schema.id_attribute_select"),
          },
          "basic_attribute_schema_expg2" => {
            "1" => eref("express_support_resource_schema" \
                        ".label_ISO_DIS_10303-108_2025_Annex_D"),
          },
        ),
      },
    )

    result = described_class.new(docs_dir).bind

    expect(result.pages).to eq(2)
    expect(result.bound).to eq(3)
    expect(result.skipped).to eq([])

    fig1 = hrefs_of("basic_attribute_schema/doc_basic_attribute_schema.html",
                    "basic_attribute_schema_expg1")
    expect(fig1).to contain_exactly(
      "2",
      "../support_resource_schema/doc_support_resource_schema.html" \
      "#support_resource_schema.identifier",
      "#basic_attribute_schema.id_attribute_select",
      "#basic_attribute_schema",
    )

    fig2 = hrefs_of("basic_attribute_schema/doc_basic_attribute_schema.html",
                    "basic_attribute_schema_expg2")
    expect(fig2).to contain_exactly(
      "../support_resource_schema/doc_support_resource_schema.html" \
      "#support_resource_schema.label",
      "#basic_attribute_schema",
    )
  end

  it "keeps ordinals whose target carries no live anchor, and pages " \
     "without presentation XML" do
    write_tree(
      pages: {
        "support_resource_schema" =>
          schema_page("support_resource_schema"),
        "basic_attribute_schema" => schema_page(
          "basic_attribute_schema",
          { "basic_attribute_schema_expg1" => %w[1 2] },
        ),
        "lonely_schema" => schema_page("lonely_schema"),
      },
      presentations: {
        "basic_attribute_schema" => schema_presentation(
          "basic_attribute_schema",
          "basic_attribute_schema_expg1" => {
            "1" => eref("express_support_resource_schema.undeclared_thing"),
            "2" => eref("express_absent_schema.identifier"),
          },
        ),
      },
    )

    result = described_class.new(docs_dir).bind

    expect(result.bound).to eq(0)
    expect(result.skipped).to eq([])

    fig = hrefs_of("basic_attribute_schema/doc_basic_attribute_schema.html",
                   "basic_attribute_schema_expg1")
    expect(fig).to contain_exactly("1", "2", "#basic_attribute_schema")
  end

  it "binds a schema-level eref to the owning page's schema anchor and " \
     "is idempotent" do
    write_tree(
      pages: {
        "support_resource_schema" =>
          schema_page("support_resource_schema"),
        "basic_attribute_schema" => schema_page(
          "basic_attribute_schema",
          { "basic_attribute_schema_expg1" => %w[7] },
        ),
      },
      presentations: {
        "basic_attribute_schema" => schema_presentation(
          "basic_attribute_schema",
          "basic_attribute_schema_expg1" => {
            "7" => eref("express_support_resource_schema"),
          },
        ),
      },
    )

    first = described_class.new(docs_dir).bind
    expect(first.bound).to eq(1)

    fig = hrefs_of("basic_attribute_schema/doc_basic_attribute_schema.html",
                   "basic_attribute_schema_expg1")
    expect(fig).to contain_exactly(
      "../support_resource_schema/doc_support_resource_schema.html" \
      "#support_resource_schema",
      "#basic_attribute_schema",
    )

    second = described_class.new(docs_dir).bind
    expect(second.bound).to eq(0)
  end

  it "stamps ordinals this tree cannot resolve, and binds stamped " \
     "anchors once the owning page appears" do
    write_tree(
      pages: {
        "basic_attribute_schema" => schema_page(
          "basic_attribute_schema",
          { "basic_attribute_schema_expg1" => %w[1] },
        ),
      },
      presentations: {
        "basic_attribute_schema" => schema_presentation(
          "basic_attribute_schema",
          "basic_attribute_schema_expg1" => {
            "1" => eref("express_support_resource_schema.identifier"),
          },
        ),
      },
    )

    # The owning page is another shard's output: absent here, so the
    # ordinal stays and carries its bibitemid for a later pass.
    first = described_class.new(docs_dir).bind
    expect(first.bound).to eq(0)
    fig = hrefs_of("basic_attribute_schema/doc_basic_attribute_schema.html",
                   "basic_attribute_schema_expg1")
    expect(fig).to contain_exactly("1", "#basic_attribute_schema")
    stamps = stamped_of(
      "basic_attribute_schema/doc_basic_attribute_schema.html",
    )
    expect(stamps).to eq(
      "1" => "express_support_resource_schema.identifier",
    )

    # The owning page arrives (the stitch merged the trees): the stamped
    # anchor binds and loses its stamp.
    support_page = docs_dir
      .join("support_resource_schema/doc_support_resource_schema.html")
    docs_dir.join("support_resource_schema").mkpath
    support_page.write(schema_page("support_resource_schema"))

    second = described_class.new(docs_dir).bind
    expect(second.bound).to eq(1)
    cross = "../support_resource_schema/doc_support_resource_schema.html" \
            "#support_resource_schema.identifier"
    expect(hrefs_of("basic_attribute_schema/doc_basic_attribute_schema.html",
                    "basic_attribute_schema_expg1")).to contain_exactly(
                      cross,
                      "#basic_attribute_schema",
                    )
    expect(stamped_of(
             "basic_attribute_schema/doc_basic_attribute_schema.html",
           )).to eq({})
  end

  it "binds stamps on pages the published tree carries without their " \
     "presentation XML" do
    # The ship-time pass runs over the unioned part sites: the pages
    # carry their stamps, the build XMLs do not ride the artifacts.
    write_tree(
      pages: {
        "support_resource_schema" =>
          schema_page("support_resource_schema"),
        "basic_attribute_schema" => schema_page(
          "basic_attribute_schema",
          { "basic_attribute_schema_expg1" => %w[1] },
        ),
      },
      presentations: {},
    )
    page = docs_dir.join(
      "basic_attribute_schema/doc_basic_attribute_schema.html",
    )
    doc = Leptris::XML.parse_html(page.read)
    doc.xpath("//*[local-name() = 'svg']//*[local-name() = 'a']")
      .find { |a| a["href"] == "1" }["data-svgmap-bibitemid"] =
      "express_support_resource_schema.identifier"
    page.write(doc.to_html)

    result = described_class.new(docs_dir).bind

    expect(result.bound).to eq(1)
    expect(stamped_of(
             "basic_attribute_schema/doc_basic_attribute_schema.html",
           )).to eq({})
    cross = "../support_resource_schema/doc_support_resource_schema.html" \
            "#support_resource_schema.identifier"
    expect(hrefs_of("basic_attribute_schema/doc_basic_attribute_schema.html",
                    "basic_attribute_schema_expg1")).to include(cross)
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
