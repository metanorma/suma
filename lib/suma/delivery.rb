# frozen_string_literal: true

module Suma
  # SRL delivery subsystem (TCSC410303-2952): merge independently rendered
  # per-part sites and resolve their unresolved cross-document references.
  module Delivery
    autoload :FrameNav, "suma/delivery/frame_nav"
    autoload :CrossPageFragments, "suma/delivery/cross_page_fragments"
    autoload :Pack, "suma/delivery/pack"
    autoload :Plan, "suma/delivery/plan"
    autoload :SiteVerifier, "suma/delivery/site_verifier"
    autoload :Stitcher, "suma/delivery/stitcher"
  end
end
