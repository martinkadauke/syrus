module PluginRouteDispatch
  extend ActiveSupport::Concern

  private

  def dispatch_plugin_route!(route)
    controller_path, action_name = route.controller.split("#", 2)
    raise ActionController::RoutingError, "Invalid plugin route target" if controller_path.blank? || action_name.blank?

    controller_class = "#{controller_path.camelize}Controller".constantize
    raise ActionController::RoutingError, "Invalid plugin route controller" unless controller_class < ActionController::Metal

    request.path_parameters.merge!(route.params)
    request.path_parameters.delete(:plugin_route)

    controller_class.dispatch(action_name, request, response)
  end
end
