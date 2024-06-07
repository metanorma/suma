# frozen_string_literal: true

require_relative "../utils"
require "shale"

module Suma
  module ToReplace
    module CollectionConfig
      class CompileOptions < Shale::Mapper
        attribute :no_install_fonts, Shale::Type::Boolean, default: -> { true }
        attribute :agree_to_terms, Shale::Type::Boolean, default: -> { true }
      end

      class BibdataTitle < Shale::Mapper
        attribute :language, Shale::Type::String
        attribute :content, Shale::Type::String
      end

      class BibdataDocid < Shale::Mapper
        attribute :type, Shale::Type::String
        attribute :id, Shale::Type::String
      end

      class BibdataContributor < Shale::Mapper
        attribute :name, Shale::Type::String
        attribute :abbreviation, Shale::Type::String
      end

      class BibdataCopyright < Shale::Mapper
        attribute :owner, BibdataContributor
        attribute :from, Shale::Type::String
      end

      class Bibdata < Shale::Mapper
        attribute :title, BibdataTitle, collection: true
        attribute :type, Shale::Type::String
        attribute :docid, BibdataDocid
        attribute :edition, Shale::Type::Integer
        attribute :copyright, BibdataCopyright
      end

      class ManifestItem < Shale::Mapper
        attribute :identifier, Shale::Type::String
        attribute :level, Shale::Type::String
        attribute :title, Shale::Type::String
        attribute :attachment, Shale::Type::Boolean
        attribute :sectionsplit, Shale::Type::Boolean
        attribute :file, Shale::Type::String
        attribute :docref, ManifestItem, collection: true

        yaml do
          map "identifier", to: :identifier
          map "level", to: :level
          map "title", to: :title
          map "attachment", to: :attachment
          map "sectionsplit", to: :sectionsplit
          map "file", to: :file
          map "fileref", to: :fileref
          map "docref", to: :docref
          map "fileref", using: { from: :fileref_from_yaml, to: :fileref_to_yaml }
        end

        def fileref_from_yaml(model, value)
          # Utils.log "model #{model}, value #{value}"
          # file_from_yaml(model, value)
          model.file ||= value
        end

        def fileref_to_yaml(_model, _doc)
          nil
        end
      end

      class Manifest < Shale::Mapper
        attribute :level, Shale::Type::String
        attribute :title, Shale::Type::String
        attribute :sectionsplit, Shale::Type::Boolean
        attribute :docref, ManifestItem, collection: true

        def attachments
          docref.detect do |ref|
            ref.level == "attachments"
          end&.docref
        end

        def documents
          docref.detect do |ref|
            ref.level == "document"
          end&.docref
        end
      end

      class Config < Shale::Mapper
        attr_accessor :path

        attribute :directives, Shale::Type::String, collection: true
        attribute :bibdata, Bibdata
        attribute :manifest, Manifest
        attribute :format, Shale::Type::String, collection: true, default: -> { [:html] }
        attribute :output_folder, Shale::Type::String
        attribute :coverpage, Shale::Type::String, default: -> { "cover.html" }
        attribute :compile, CompileOptions
        attribute :prefatory_content, Shale::Type::String
        attribute :final_content, Shale::Type::String

        def self.from_file(path)
          from_yaml(File.read(path))
        end
      end
    end
  end
end
