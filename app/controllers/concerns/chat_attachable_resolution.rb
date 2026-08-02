# Attachable-resolution helpers extracted from Api::V1::App::ChatsController.
#
# These resolve the concrete Repository/Job/Document/Epic a request refers to —
# by explicit id, by repository slug, by the most-recent chat repository, or by
# falling back to the first attachment-search result. They are pure controller
# helpers (reading `params` and `Current.user`), and `attachable_from_params`
# leans on the sibling ChatAttachmentSearch concern's `attachment_search_results`
# via the shared include. Kept private on include.
module ChatAttachableResolution
  private

  ATTACHMENT_FINDER_METHODS = {
    "Repository" => :find_repository_attachment,
    "Job"        => :find_job_attachment,
    "Document"   => :find_document_attachment,
    "Epic"       => :find_epic_attachment
  }.freeze

  def most_recent_chat_repository
    recent_repo_id = Current.user.accessible_chat_sessions
      .joins(:repository_attachments)
      .order("chat_sessions.created_at DESC")
      .limit(1)
      .pick("chat_attachments.attachable_id")

    Current.user.repositories.active.find_by(id: recent_repo_id) if recent_repo_id
  end

  def repository_from_params
    id = params[:repository_id].presence
    return unless id

    Current.user.repositories.active.find(id)
  end

  def attachable_from_params(chat_session)
    type = normalized_attachable_type
    return unless type

    id = params[:attachable_id].presence || params.dig(:chat_attachment, :attachable_id).presence
    return find_attachable_by_id(type, id) if id.present?
    return repository_from_slug if type == "Repository" && params[:repository_slug].present?

    attachment_search_results(chat_session).first
  end

  def repository_from_slug
    owner, name = params[:repository_slug].to_s.strip.split("/", 2)
    return if owner.blank? || name.blank?

    Current.user.repositories.active.find_by(owner: owner, name: name)
  end

  def normalized_attachable_type
    raw = params[:attachable_type].presence || params.dig(:chat_attachment, :attachable_type).presence
    return unless raw

    type = %w[Document RepositoryDocument].include?(raw.to_s) ? "Document" : raw.to_s
    ChatAttachment::ATTACHABLE_TYPES.include?(type) ? type : nil
  end

  def find_attachable_by_id(type, id)
    method_name = ATTACHMENT_FINDER_METHODS[type]
    send(method_name, id) if method_name
  end

  def find_repository_attachment(id)
    Current.user.repositories.active.find(id)
  end

  def find_job_attachment(id)
    Current.user.jobs.find(id)
  end

  def find_document_attachment(id)
    Document.where(user: Current.user, attachable_type: "Repository").find(id)
  end

  def find_epic_attachment(id)
    Current.user.epics.find(id)
  end
end
