# frozen_string_literal: true

require "spec_helper"
require "suma/delivery/cross_page_fragments"
require "tmpdir"

# The assertions pair the repair counts with the remapped href by
# design; the page fixtures are per-example lets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, RSpec/ScatteredLet, RSpec/ImplicitBlockExpectation

RSpec.describe Suma::Delivery::CrossPageFragments do
  let(:site_dir) { Pathname.new(Dir.mktmpdir("suma_fragment_repair")) }

  after do
    FileUtils.rm_rf(site_dir)
  end

  def write_pages(pages)
    pages.each do |name, body|
      path = site_dir.join(name)
      path.dirname.mkpath
      path.write(body)
    end
  end

  # Writes the pages, runs the repair, then returns [result,
  # first-href-on-page].
  def repair_and_first_href(pages, page)
    write_pages(pages)
    result = described_class.new(site_dir).repair
    a = Leptris::XML.parse_html(site_dir.join(page).read).css("a").first
    [result, a&.[]("href")]
  end

  let(:cross_page_pair) do
    {
      "a.html" => "<html><body><p id='the_target'>declaration</p>" \
                  "<a href='#elsewhere'>x</a></body></html>",
      "b.html" => "<html><body><a href='#the_target'>term</a></body></html>",
    }
  end

  let(:own_page) do
    { "a.html" => "<html><body><p id='local'>local</p>" \
                  "<a href='#local'>self</a></body></html>" }
  end

  let(:stamped_declaration_pages) do
    target = "geometry_schema.curve_ISO_10303-42_2025"
    {
      "doc_a.html" => "<html><body><p id='#{target}'>curve</p></body></html>",
      "doc_b.html" => "<html><body><a href='#curve'>curve</a></body></html>",
    }
  end

  let(:ambiguous_pages) do
    {
      "one.html" => "<html><body><p id='shared'>a</p>" \
                    "<a href='#shared'>x</a></body></html>",
      "two.html" => "<html><body><p id='shared'>b</p></body></html>",
    }
  end

  let(:ghost_page) do
    { "solo.html" => "<html><body><a href='#nowhere'>ghost</a></body></html>" }
  end

  it "repoints a fragment whose id renders on exactly one other page" do
    result, href = repair_and_first_href(cross_page_pair, "b.html")
    expect([result[:remapped], href]).to eq([1, "a.html#the_target"])
  end

  it "leaves own-page fragments untouched" do
    result, href = repair_and_first_href(own_page, "a.html")
    expect([result[:own], href]).to eq([1, "#local"])
  end

  it "resolves a bare declaration name to its stamped anchor's page" do
    # The svgmap-hotspot family: the synthesized href carries the plain
    # declaration name; the declaring page renders the stamped anchor
    # `<scope>_ISO_<doc>_<year>`.
    result, href = repair_and_first_href(stamped_declaration_pages,
                                         "doc_b.html")
    expect(result[:remapped]).to eq(1)
    expect(href)
      .to eq("doc_a.html#geometry_schema.curve_ISO_10303-42_2025")
  end

  it "leaves an ambiguous bare name untouched" do
    # Two pages render the same bare fragment id — no unique target, no
    # guess.
    result, href = repair_and_first_href(ambiguous_pages, "one.html")
    expect([result[:ambiguous], href]).to eq([1, "#shared"])
  end

  it "counts unresolved fragments without touching them" do
    result, href = repair_and_first_href(ghost_page, "solo.html")
    expect([result[:unresolved], href]).to eq([1, "#nowhere"])
  end

  it "skips unscoped anchors instead of crashing on them" do
    pages = stamped_declaration_pages.merge(
      "doc_a.html" => "<html><body>" \
                      "<p id='plain_anchor_ISO_10303-42_2025'>" \
                      "not a scope</p>" \
                      "<p id='geometry_schema.curve_ISO_10303-42_2025'>" \
                      "curve</p>" \
                      "</body></html>",
    )
    result, href = repair_and_first_href(pages, "doc_b.html")
    # The plain anchor (its stem ends with a stamp, so it has no scope
    # match) must be tolerated; the scoped one still resolves.
    expect([result[:remapped],
            href]).to eq([1,
                          "doc_a.html#geometry_schema.curve_ISO_10303-42_2025"])
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, RSpec/ScatteredLet, RSpec/ImplicitBlockExpectation
