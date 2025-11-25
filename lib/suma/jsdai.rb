module Suma
  module Jsdai
  end
end

require_relative "jsdai/figure"

# Configure XML adapter to Nokogiri because Ox goes into a "stack level too
# deep" error, for unknown reasons
Lutaml::Model::Config.configure do |config|
  config.xml_adapter_type = :nokogiri
end
