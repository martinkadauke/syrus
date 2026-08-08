module Admin
  class PluginPagesPayload
    def as_json(*)
      {
        pages: Syrus::PluginRegistry.providers_for(:admin_page)
          .flat_map { |provider| pages_for(provider) }
          .sort_by { |page| [ page[:order].to_i, page[:label].to_s ] }
      }
    end

    private

    def pages_for(provider)
      PerformanceLogging.plugin_call(extension_point: :admin_page, provider: provider, operation: :admin_pages) do
        Array(provider.admin_pages).map { |page| page_payload(page) }
      end
    end

    def page_payload(page)
      page = page.to_h.symbolize_keys
      {
        id: page.fetch(:id).to_s,
        label: page.fetch(:label).to_s,
        path: page.fetch(:path).to_s,
        paths: Array(page[:paths].presence || page[:path]).map(&:to_s),
        order: page[:order].to_i
      }
    end
  end
end
