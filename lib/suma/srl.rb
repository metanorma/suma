# frozen_string_literal: true

module Suma
  # SRL delivery subsystem (TCSC410303-2952): merge independently rendered
  # per-part sites and resolve their unresolved cross-document references.
  module Srl
    autoload :FrameNav, "suma/srl/frame_nav"
    autoload :SiteVerifier, "suma/srl/site_verifier"
    autoload :Stitcher, "suma/srl/stitcher"
  end
end
