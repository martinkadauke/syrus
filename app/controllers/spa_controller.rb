class SpaController < ApplicationController
  layout "spa"
  before_action :require_admin, if: :admin_spa_path?

  def show
  end

  private

  def admin_spa_path?
    request.path == "/admin" ||
      request.path.start_with?("/admin/") ||
      request.path == "/app-shell/admin" ||
      request.path.start_with?("/app-shell/admin/") ||
      request.path == "/invitations" ||
      request.path == "/app-shell/invitations"
  end
end
