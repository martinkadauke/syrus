class InvitationsController < ApplicationController
  before_action :require_admin
  helper_method :invitations_form_path, :invitation_destroy_path

  def index
    @pending_invitations = Invitation.pending.order(created_at: :desc)
    @invitation = Invitation.new
  end

  def create
    @invitation = Invitation.new(invitation_params.merge(invited_by: Current.user))
    if @invitation.save
      redirect_to invitations_redirect_path, notice: "Invitation created for #{@invitation.email_address}."
    else
      @pending_invitations = Invitation.pending.order(created_at: :desc)
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    Invitation.find(params[:id]).destroy
    redirect_to invitations_redirect_path, notice: "Invitation revoked."
  end

  private

  def invitation_params
    params.expect(invitation: [ :email_address ])
  end

  def invitations_form_path
    legacy_invitations_request? ? legacy_invitations_path : invitations_path
  end

  def invitation_destroy_path(invitation)
    legacy_invitations_request? ? legacy_invitation_path(invitation) : invitation_path(invitation)
  end

  def invitations_redirect_path
    legacy_invitations_request? ? legacy_invitations_path : invitations_path
  end

  def legacy_invitations_request?
    request.path.start_with?("/invitations/legacy")
  end
end
