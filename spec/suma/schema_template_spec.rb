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

      it "emits the schema id as the unnumbered section heading" do
        rendered = template.render("schemas.yaml")
        expect(rendered).to include("[%unnumbered]\n== action_schema")
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
        # the anchor block emits one bookmark per element collection
        expect(rendered).to include("[[action_schema.entities")
        expect(rendered).to include("[[action_schema.types")
        expect(rendered).to include("[[action_schema.constants")
        expect(rendered).to include("[[action_schema.functions")
        expect(rendered).to include("[[action_schema.procedures")
        expect(rendered).to include("[[action_schema.rules")
        expect(rendered).to include("[[action_schema.subtype_constraints")
      end

      it "only declares xml as the output extension" do
        rendered = template.render("schemas.yaml")
        expect(rendered).to include(":mn-output-extensions: xml\n")
      end
    end
  end

  describe "Plain vs Document" do
    it "Plain does not emit the [[<schema_id>]] section anchor that Document does" do
      plain = described_class::Plain.new("action_schema").render("schemas.yaml")
      document = described_class::Document.new("action_schema").render("schemas.yaml")
      expect(plain).not_to include("[[action_schema]]\n[%unnumbered,type=express]")
      expect(document).to include("[[action_schema]]\n[%unnumbered,type=express]")
    end
  end
end
