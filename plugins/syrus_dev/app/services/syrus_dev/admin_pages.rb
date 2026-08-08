module SyrusDev
  class AdminPages
    include Syrus::Plugin::AdminPage

    def self.admin_pages
      [
        {
          id: "syrus_dev.performance",
          label: "Performance",
          label_key: "syrus_dev:nav_performance",
          path: "/admin/performance",
          paths: [ "/admin/performance" ],
          component: "syrus_dev/AdminPerformance",
          order: 40
        }
      ]
    end
  end
end
