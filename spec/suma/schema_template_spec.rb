# frozen_string_literal: true

require "suma/schema_template"

RSpec.describe Suma::SchemaTemplate do
  describe "Plain" do
    let(:template) { described_class::Plain.new("action_schema") }

    it "returns xml,html extensions" do
      expect(template.extensions).to eq("xml,html")
    end

    describe "#render" do
      it "emits the schema id as the AsciiDoc document title" do
        expect(template.render("schemas.yaml")).to start_with("= action_schema\n")
      end

      it "configures the lutaml-express-index with the supplied yaml path" do
        rendered = template.render("path/to/schemas.yaml")
        expect(rendered).to include(":lutaml-express-index: schemas; path/to/schemas.yaml;")
      end

      it "declares both xml and html output extensions" do
        rendered = template.render("schemas.yaml")
        expect(rendered).to include(":mn-output-extensions: xml,html")
      end

      it "opens the lutaml_express_liquid block iterating context.schemas" do
        rendered = template.render("schemas.yaml")
        expect(rendered).to include("[lutaml_express_liquid,schemas,context]")
        expect(rendered).to include("{% for schema in context.schemas %}")
      end

      it "renders the schema with live cross-reference links under anchors" do
        rendered = template.render("schemas.yaml")
        aggregate_failures do
          expect(rendered).to include("[[action_schema]]")
          expect(rendered).to include("[%unnumbered,type=express]")
          expect(rendered).to include("{{ schema.formatted_hyperlinked_adoc }}")
          expect(rendered).to include('[source%unnumbered,subs="+macros"]')
        end
      end

      it "emits element anchors including bare entity.attribute bookmarks" do
        rendered = template.render("schemas.yaml")
        aggregate_failures do
          # element anchors qualify with the schema's declared id
          expect(rendered).to include("[[{{ schema.id")
          expect(rendered).to include(".entities")
          # Expressir links attributes as bare entity.attribute pairs
          expect(rendered).to include("[[{{thing.id")
        end
      end
    end
  end

  describe "Document" do
    let(:template) { described_class::Document.new("action_schema") }

    it "returns xml-only extensions" do
      expect(template.extensions).to eq("xml")
    end

    describe "#render" do
      it "anchors the section with [[action_schema]] for cross-referencing" do
        rendered = template.render("schemas.yaml")
        expect(rendered).to include("[[action_schema]]")
      end

      it "declares the section as type=express" do
        rendered = template.render("schemas.yaml")
        expect(rendered).to include("[%unnumbered,type=express]")
      end

      it "includes per-collection anchor ids (entities, types, constants, etc.)" do
        rendered = template.render("schemas.yaml")
        # the anchor block emits one bookmark per element collection,
        # qualified by the schema's declared id (a Liquid reference)
        expect(rendered).to include("[[{{ schema.id")
        %w[entities types constants functions procedures rules
           subtype_constraints].each do |collection|
          expect(rendered).to include(".#{collection}]]")
        end
      end

      it "only declares xml as the output extension" do
        rendered = template.render("schemas.yaml")
        expect(rendered).to include(":mn-output-extensions: xml\n")
      end
    end
  end

  describe "Plain vs Document" do
    it "differs only in output extensions" do
      plain = described_class::Plain.new("action_schema")
      document = described_class::Document.new("action_schema")

      aggregate_failures do
        expect(plain.extensions).to eq("xml,html")
        expect(document.extensions).to eq("xml")
        expect(plain.render("schemas.yaml")).to eq(
          document.render("schemas.yaml")
            .sub(":mn-output-extensions: xml\n",
                 ":mn-output-extensions: xml,html\n"),
        )
      end
    end
  end
end
