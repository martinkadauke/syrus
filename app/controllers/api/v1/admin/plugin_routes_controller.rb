module Api
  module V1
    module Admin
      class PluginRoutesController < BaseController
        include PluginRouteDispatch

        def show
          route = PluginRouteResolver.find(request, controller_prefix: "api/v1/admin/")
          return render_error("not_found", "Plugin route not found", status: :not_found) unless route

          dispatch_plugin_route!(route)
        end
      end
    end
  end
end
