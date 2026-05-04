module Admin
  # Shared base for /admin/* controllers. All admin views are gated
  # on the existing first-user-is-admin model — Current.user.admin?
  # check via require_admin (defined in ApplicationController).
  class BaseController < ApplicationController
    before_action :require_admin
  end
end
