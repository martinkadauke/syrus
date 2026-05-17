class Repositories::ChatsController < ApplicationController
  PAGE_SIZE = 30

  before_action :load_repository
  before_action :load_chat_session, only: %i[ message stop refresh reset messages ]
  before_action :load_pending_action, only: %i[ confirm_pending_action destroy_pending_action ]
  before_action :load_proposal, only: %i[ confirm_proposal reject_proposal ]

  # Renders the repository chat home. Picks up the newest chat for
  # this user+repository, or falls back to an empty-state view that
  # waits for the operator's first message before creating any
  # ChatSession. Visiting the page must NOT mutate state — that's why
  # `POST /repositories/:id/chats` exists for explicit chat creation.
  def show
    @chat_session = current_chat_session
    @chat_available = Current.user.claude_oauth_token.present?
    @messages, @has_more_older = paginated_tail(@chat_session)
    @pending_actions = @chat_session ? @chat_session.pending_actions.where(state: "pending").order(:created_at, :id) : []
    @turn_in_flight = @chat_session&.turn_in_flight? || false
    @attachment_groups = @chat_session ? @chat_session.chat_attachments.includes(:attachable).order(:attachable_type, :attached_at, :id).group_by(&:attachable_type) : {}
    @documents_in_scope = @chat_session ? @chat_session.attached_documents_in_scope.includes(:attachable).order(:title, :id) : Document.none
    @attachment_results = []
    @bookmarks = @chat_session ? @chat_session.bookmarks.includes(:chat_message) : []
  end

  # Returns an HTML fragment of the next page of older messages, for
  # the infinite-scroll-up behavior in chat_controller.js. The fragment
  # is rendered without a layout so it can be parsed and prepended
  # directly into the live stream container.
  def messages
    before_id = params[:before].to_i
    fetched = @chat_session.messages.includes(:proposal)
                .where("id < ?", before_id)
                .order(created_at: :desc, id: :desc)
                .limit(PAGE_SIZE + 1)
                .to_a
    has_more = fetched.size > PAGE_SIZE
    older = fetched.first(PAGE_SIZE).reverse

    response.headers["X-Chat-Has-More-Older"] = has_more ? "true" : "false"
    render partial: "repositories/chats/message_stream",
           locals: {
             items: ChatMessageGrouper.group(older),
             repository: @repository
           },
           layout: false
  end

  def create
    text = message_text
    if text.blank?
      # Empty POST is the "New chat" button — defer creating any
      # ChatSession until the operator actually has something to
      # send. Re-rendering the show page with new_chat=1 lets the
      # view clear any displayed chat without leaving a turd behind
      # in the DB.
      redirect_to repository_chats_path(@repository, new_chat: "1")
      return
    end

    chat_session = nil
    user_message = nil
    ApplicationRecord.transaction do
      chat_session = ChatSession.create!(
        user: Current.user,
        repository: @repository,
        title: text.truncate(80),
        last_message_at: Time.current
      )
      user_message = chat_session.messages.create!(role: "user", content: { "text" => text })
    end

    ChatTurnJob.perform_later(chat_session.id, user_message.id)
    redirect_to repository_chats_path(@repository), notice: "Message sent."
  end

  def message
    text = message_text
    if text.blank?
      redirect_to repository_chats_path(@repository), alert: "Message cannot be blank."
      return
    end

    user_message = nil
    ApplicationRecord.transaction do
      @chat_session.update!(last_message_at: Time.current)
      user_message = @chat_session.messages.create!(role: "user", content: { "text" => text })
    end

    ChatTurnJob.perform_later(@chat_session.id, user_message.id)
    redirect_to repository_chats_path(@repository), notice: "Message sent."
  end

  def stop
    @chat_session.update!(stop_requested_at: Time.current)
    @chat_session.broadcast_controls
    redirect_to repository_chats_path(@repository), notice: "Stop requested."
  end

  def refresh
    ChatWorkspaceJob.perform_later(@chat_session.id, action: :refresh)
    redirect_to repository_chats_path(@repository), notice: "Repository refresh queued."
  end

  def reset
    ChatWorkspaceJob.perform_later(@chat_session.id, action: :reset)
    redirect_to repository_chats_path(@repository), notice: "Workspace reset queued."
  end

  def confirm_pending_action
    if @pending_action.confirm!(user: Current.user)
      record = @pending_action.result
      notice = case record
               when ScheduledTask then "Scheduled task created: #{record.name}."
               else "Pending action confirmed."
               end
      redirect_to repository_chats_path(@repository), notice: notice
    else
      redirect_to repository_chats_path(@repository), alert: "Pending action is no longer active."
    end
  rescue ActiveRecord::RecordInvalid => e
    message = e.record.errors.full_messages.to_sentence.presence || "Pending action could not be confirmed."
    redirect_to repository_chats_path(@repository), alert: message
  rescue ActiveRecord::RecordNotFound, ArgumentError => e
    redirect_to repository_chats_path(@repository), alert: e.message
  end

  def destroy_pending_action
    rejection = @pending_action.action_type != "schedule_recurring"
    result = if rejection
      @pending_action.reject!
    else
      @pending_action.cancel!(user: Current.user)
    end

    if result
      notice = rejection ? "Pending action rejected." : "Pending action cancelled."
      redirect_to repository_chats_path(@repository), notice: notice
    else
      redirect_to repository_chats_path(@repository), alert: "Pending action is no longer active."
    end
  rescue ActiveRecord::RecordNotFound => e
    redirect_to repository_chats_path(@repository), alert: e.message
  end

  def confirm_proposal
    if @proposal.confirmed?
      redirect_to repository_chats_path(@repository), alert: "Proposal is already confirmed."
      return
    end

    unless @proposal.proposed?
      redirect_to repository_chats_path(@repository), alert: "Proposal is no longer proposed."
      return
    end

    result = if @proposal.epic_bundle?
      ChatEpicProposalMaterializer.new(user: Current.user).file!(@proposal)
    else
      ChatProposalFiler.new(user: Current.user, repository: @proposal.effective_repository || @repository).file!([ @proposal ])
    end
    record = result.respond_to?(:epic) && result.epic ? result.epic : result.jobs.first || @proposal.reload.materialized_record
    notice = case record
    when Job
      "Proposal confirmed and filed as Job ##{record.id}."
    when Epic
      "Proposal confirmed and filed as #{record.display_number}."
    else
      "Proposal confirmed."
    end
    redirect_to repository_chats_path(@repository), notice: notice
  rescue ArgumentError => e
    redirect_to repository_chats_path(@repository), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to repository_chats_path(@repository), alert: e.record.errors.full_messages.to_sentence
  end

  def reject_proposal
    if @proposal.proposed?
      @proposal.update!(state: "rejected", rejected_at: Time.current)
      redirect_to repository_chats_path(@repository), notice: "Proposal rejected."
    else
      redirect_to repository_chats_path(@repository), alert: "Proposal is no longer proposed."
    end
  end

  private

  def load_repository
    @repository = Current.user.repositories.find(params[:repository_id])
  end

  def load_chat_session
    @chat_session = Current.user.chat_sessions.attached_to_repository(@repository).find(params[:id])
  end

  def load_pending_action
    @pending_action = ChatPendingAction.where(repository: @repository, user: Current.user).find(params[:id])
  end

  def load_proposal
    @proposal = proposals_scope.find(params[:proposal_id])
  end

  def proposals_scope
    ChatProposal
      .left_joins(chat_session: :chat_attachments)
      .where(
        "chat_proposals.repository_id = :repository_id OR (chat_proposals.repository_id IS NULL AND chat_attachments.attachable_type = 'Repository' AND chat_attachments.attachable_id = :repository_id)",
        repository_id: @repository.id
      )
      .distinct
  end

  def current_chat_session
    Current.user.chat_sessions
      .attached_to_repository(@repository)
      .order(last_message_at: :desc, created_at: :desc, id: :desc)
      .first
  end

  def new_chat?
    ActiveModel::Type::Boolean.new.cast(params[:new_chat])
  end

  def message_text
    params.dig(:chat_message, :text).to_s.strip
  end

  # Loads the latest PAGE_SIZE messages in chronological order plus a
  # flag for whether older messages exist. Returns an empty pair when
  # there is no chat_session (initial empty-state render).
  def paginated_tail(chat_session)
    return [ [], false ] unless chat_session

    scope = chat_session.messages.includes(:proposal)
    fetched = scope.order(created_at: :desc, id: :desc).limit(PAGE_SIZE + 1).to_a
    has_more = fetched.size > PAGE_SIZE
    [ fetched.first(PAGE_SIZE).reverse, has_more ]
  end
end
