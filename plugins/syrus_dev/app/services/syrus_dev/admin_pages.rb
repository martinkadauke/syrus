module SyrusDev
  class AdminPages
    include Syrus::Plugin::AdminPage

    def self.admin_pages
      [
        {
          id: "syrus_dev.performance",
          label: "Performance",
          path: "/admin/performance",
          paths: [ "/admin/performance" ],
          order: 40
        }
      ]
    end
  end
end
