module Syrus
  module Plugin
    # Marker interface for plugin-provided admin pages.
    #
    # Providers registered as :admin_page expose .admin_pages metadata. The host
    # uses that metadata to add SPA routes and admin navigation entries.
    module AdminPage
    end
  end
end
