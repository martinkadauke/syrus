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
        },
        {
          id: "syrus_dev.operational_logs",
          label: "Operational Logs",
          label_key: "admin:nav_operational_logs",
          path: "/admin/operational_logs",
          paths: [ "/admin/operational_logs" ],
          component: "syrus_dev/AdminOperationalLogs",
          order: 45
        }
      ]
    end
  end
end
