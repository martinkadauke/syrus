class InvitationsController < ApplicationController
  before_action :require_admin

  def index
    @pending_invitations = Invitation.pending.order(created_at: :desc)
    @invitation = Invitation.new
  end

  def create
    @invitation = Invitation.new(invitation_params.merge(invited_by: Current.user))
    if @invitation.save
      redirect_to invitations_path, notice: "Invitation created for #{@invitation.email_address}."
    else
      @pending_invitations = Invitation.pending.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    Invitation.find(params[:id]).destroy
    redirect_to invitations_path, notice: "Invitation revoked."
  end

  private

  def invitation_params
    params.expect(invitation: [ :email_address ])
  end
end
