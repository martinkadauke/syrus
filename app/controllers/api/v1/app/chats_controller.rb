module Api
  module V1
    module App
      class ChatsController < BaseController
        include ChatAttachmentSearch
        include ChatAttachableResolution
        include ChatIndexPayload
        include ChatPendingActions
        include ChatProposalOutcome
        include ChatProviderOptions

        PAGE_SIZE = ChatSession::MESSAGE_PAGE_SIZE
        HIDDEN_CHATS_PAGE_SIZE = 20
        SEARCH_PAGE_SIZE = 20
        SEARCH_TOP_MATCHES = 3
        CHAT_TURN_ENQUEUE_RETRY_DELAYS = [ 0.05, 0.2 ].freeze
        CHAT_STREAM_POLL_INTERVAL = 0.25.seconds
        CHAT_STREAM_TIMEOUT = 30.minutes
        CHAT_ATTACHMENT_ALLOWED_MIME_TYPES = %w[
          image/jpeg
          image/png
          image/gif
          image/webp
          application/pdf
        ].freeze
        CHAT_ATTACHMENT_MAX_BASE64_BYTES = 7.megabytes
        PRODUCT_OWNER_EPIC_JOB_MESSAGE = "Product owners cannot add Jobs to Epics directly — " \
          "claim the Epic as a developer to elaborate it.".freeze

        def index
          render json: {
            groups: recent_chats_index_json,
            repositories: Current.user.repositories.active.order(:owner, :name).map { |repository| repository_json(repository) }
          }
        end

        def more
          before_id = Integer(params[:before_id], exception: false)
          if before_id.blank? || before_id <= 0
            render_error("validation_failed", "before_id is required.", status: :unprocessable_content)
            return
          end

          repository_id = chat_index_repository_id
          return if performed?

          scope = chat_index_group_scope(repository_id)
          cursor = scope.find_by(id: before_id)
          unless cursor
            render_error("not_found", "Chat cursor was not found.", status: :not_found)
            return
          end

          chats, has_more = paginated_chat_index_group(scope, before_chat: cursor)
          render json: {
            chats: chats.map { |chat_session| chat_index_json(chat_session) },
            has_more: has_more
          }
        end

        def show
          render json: chat_payload(find_chat_session)
        end

        def update
          chat_session = ChatSession.find(params[:id])
          unless chat_session.user_id == Current.user.id
            render_error("forbidden", "You do not have permission to update this chat.", status: :forbidden)
            return
          end

          chat_params = params[:chat]
          if chat_params.respond_to?(:key?) && chat_params.key?(:chat_provider)
            provider = normalized_chat_provider_param(chat_params[:chat_provider])
            unless provider.nil? || Current.user.chat_provider_configured?(provider)
              render_error("validation_failed", "Chat provider is not configured.", status: :unprocessable_content)
              return
            end

            chat_session.update!(chat_provider: provider)
            render json: chat_payload(chat_session.reload, message: "Chat provider updated.")
            return
          end

          if chat_params.respond_to?(:key?) && chat_params.key?(:mode)
            mode = chat_params[:mode].to_s.strip.presence
            if mode && !ChatSession::MODES.include?(mode)
              render_error("validation_failed", "Invalid mode. Must be one of: #{ChatSession::MODES.join(", ")}.", status: :unprocessable_content)
              return
            end
            if mode == "coding" && !Feature.coding_mode_enabled?
              render_error("feature_disabled", "Coding Mode is not enabled on this instance.", status: :unprocessable_content)
              return
            end
            if mode == "local" && !Feature.local_mode_enabled?
              render_error("validation_failed", "Local mode is not enabled.", status: :unprocessable_content)
              return
            end

            chat_session.update!(mode: mode)
            render json: chat_payload(chat_session.reload, message: "Chat mode updated.")
            return
          end

          pinned = if chat_params.respond_to?(:key?) && chat_params.key?(:pinned)
            params[:chat][:pinned]
          else
            params[:pinned]
          end
          if pinned.nil?
            render_error("validation_failed", "pinned is required.", status: :unprocessable_content)
            return
          end

          chat_session.update!(pinned: ActiveModel::Type::Boolean.new.cast(pinned))

          render json: chat_payload(chat_session.reload, message: chat_session.pinned? ? "Chat pinned" : "Chat unpinned")
        end

        def share
          chat_session = find_chat_session
          chat_session.with_lock do
            chat_session.update!(share_token: SecureRandom.uuid) if chat_session.share_token.blank?
          end

          render json: { share_url: shared_chat_url(token: chat_session.share_token) }
        end

        def search
          query = search_query
          scope = filtered_chat_search_scope
          return if performed?

          page = search_page

          if query.present?
            render json: search_payload_for_query(scope, query, page)
          else
            render json: search_payload_for_scope(scope, page)
          end
        end

        def search_messages
          query = search_query
          if query.blank?
            render_error("validation_failed", "Query is required.", status: :unprocessable_content)
            return
          end

          chat_session = Current.user.chat_sessions.visible.find(params[:chat_session_id])
          render json: {
            matches: chat_search_rows(query, chat_session_id: chat_session.id).map { |row| chat_search_match_json(row) }
          }
        end

        def hidden
          page = [ Integer(params[:page], exception: false).to_i, 1 ].max
          scope = Current.user.chat_sessions.hidden
          total = scope.count
          chats = scope
            .preload(repository_attachments: :attachable)
            .order(hidden_at: :desc, id: :desc)
            .offset((page - 1) * HIDDEN_CHATS_PAGE_SIZE)
            .limit(HIDDEN_CHATS_PAGE_SIZE)

          render json: {
            chats: chats.map { |chat_session| hidden_chat_json(chat_session) },
            total: total,
            page: page,
            per_page: HIDDEN_CHATS_PAGE_SIZE,
            total_pages: (total.to_f / HIDDEN_CHATS_PAGE_SIZE).ceil
          }
        end

        def messages
          chat_session = find_chat_session
          before_id = Integer(params[:before], exception: false)
          messages, has_more_older = paginated_before(chat_session, before_id)

          render json: {
            has_more_older: has_more_older,
            messages: messages_json(messages, repository: chat_session.repository)
          }
        end

        def new
          repository = most_recent_chat_repository
          repository ||= Current.user.repositories.active.order(:owner, :name).first

          render json: {
            default_repository_id: repository&.id
          }
        end

        # Create the first-run onboarding chat: attached to the operator's
        # first active repository, flagged onboarding (so the agent gets the
        # onboarding script), and seeded with a kickoff message so the agent
        # welcomes the operator immediately.
        def onboarding
          # Idempotent: the onboarding step (and its "open chat" follow-ups)
          # should always land on the one onboarding chat, not spawn new ones.
          existing = Current.user.onboarding_chat
          if existing
            render json: { message: "Chat opened.", redirect_to: chat_path(existing), chat: chat_json(existing) }, status: :ok
            return
          end

          repository = Current.user.repositories.active.order(:owner, :name).first
          chat_session = nil
          user_message = nil

          ApplicationRecord.transaction do
            chat_session = ChatSession.create!(
              user: Current.user,
              repository: repository,
              onboarding: true,
              last_message_at: Time.current
            )
            user_message = chat_session.messages.create!(
              role: "user",
              content: { "text" => "I just finished setting up Syrus. Show me how it works and help me get started." }
            )
          end

          enqueue_chat_title(chat_session, user_message)
          enqueue_chat_turn(chat_session, user_message)

          render json: {
            message: "Chat created.",
            redirect_to: chat_path(chat_session),
            chat: chat_json(chat_session)
          }, status: :created
        rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked, ActiveRecord::StatementTimeout, SolidQueue::Job::EnqueueError => e
          raise unless transient_chat_lock_error?(e)

          render_temporary_chat_lock_error
        end

        def create
          chat_session = create_chat_session
          return if performed?

          render json: {
            message: chat_session.messages.exists? ? "Message sent." : "Chat created.",
            redirect_to: chat_path(chat_session),
            chat: chat_json(chat_session)
          }, status: :created
        rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked, ActiveRecord::StatementTimeout, SolidQueue::Job::EnqueueError => e
          raise unless transient_chat_lock_error?(e)

          render_temporary_chat_lock_error
        end

        def message
          chat_session = find_chat_session
          text = message_text
          if text.blank? && !message_has_attachments?
            render_error("validation_failed", "Message cannot be blank.", status: :unprocessable_content)
            return
          end
          content = message_content(text)
          return if performed?

          user_message = nil
          ApplicationRecord.transaction do
            chat_session.update!(
              last_message_at: Time.current,
              title: chat_session.title.presence
            )
            user_message = chat_session.messages.create!(role: "user", content: content)
          end
          if chat_session.title.blank? && (title_message = first_user_message(chat_session))
            enqueue_chat_title(chat_session, title_message)
          end
          enqueue_chat_turn(chat_session, user_message)

          if stream_request?
            stream_chat_turn(chat_session, user_message)
            return
          end

          render json: chat_payload(chat_session.reload, message: "Message sent.")
        rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked, ActiveRecord::StatementTimeout, SolidQueue::Job::EnqueueError => e
          raise unless transient_chat_lock_error?(e)

          render_temporary_chat_lock_error
        end

        def stop
          chat_session = find_chat_session
          chat_session.update!(stop_requested_at: Time.current)
          request_chat_agent_kill!(chat_session)
          ChatStopReconciler.reconcile!(chat_session: chat_session)
          chat_session.reload.broadcast_controls if chat_session.stop_requested_at?

          render json: chat_payload(chat_session.reload, message: "Stop requested.")
        end

        def daemon_connection
          chat_session = find_chat_session

          unless Feature.local_mode_enabled?
            render_error("forbidden", "Local mode is not enabled.", status: :forbidden)
            return
          end

          unless chat_session.mode == "local"
            render_error("validation_failed", "Chat is not in local mode.", status: :unprocessable_content)
            return
          end

          state = params[:state].to_s.strip
          unless ChatSession::DAEMON_STATES.include?(state)
            render_error("validation_failed", "Invalid state. Must be one of: #{ChatSession::DAEMON_STATES.join(", ")}.", status: :unprocessable_content)
            return
          end

          attrs = { local_daemon_state: state }
          if state == "connected"
            attrs[:local_daemon_repo] = params[:repo].to_s.strip.presence
            attrs[:local_daemon_branch] = params[:branch].to_s.strip.presence
          else
            attrs[:local_daemon_repo] = nil
            attrs[:local_daemon_branch] = nil
          end

          chat_session.update!(attrs)

          render json: { message: "Daemon connection state updated." }
        end

        def switch_provider
          chat_session = find_chat_session
          provider = params[:provider].to_s.strip

          unless User::CHAT_PROVIDERS.include?(provider)
            render_error("validation_failed", "Invalid provider. Must be one of: #{User::CHAT_PROVIDERS.join(", ")}.", status: :unprocessable_content)
            return
          end

          if chat_session.turn_in_flight? || chat_session.agent_busy?
            render_error("turn_in_flight", "Cannot switch provider while a turn is in progress.", status: :unprocessable_content)
            return
          end

          SwitchChatProviderJob.perform_later(chat_session.id, provider)

          render json: { message: "Switching to #{provider}." }
        end

        def rename
          chat_session = find_chat_session
          name = chat_name
          if name.blank?
            render_error("validation_failed", "Name cannot be blank.", status: :unprocessable_content)
            return
          end

          if name.length > ChatSession::TITLE_MAX_LENGTH
            render_error("validation_failed", "Name must be #{ChatSession::TITLE_MAX_LENGTH} characters or fewer.", status: :unprocessable_content)
            return
          end

          chat_session.update!(title: name)

          render json: chat_payload(chat_session.reload, message: "Chat renamed.")
        end

        def branch
          source_chat = find_branch_source_chat_session
          return if performed?

          branched_chat = nil
          ApplicationRecord.transaction do
            branched_chat = ChatSession.create!(
              user: source_chat.user,
              repository: source_chat.repository,
              title: branch_chat_title(source_chat),
              chat_provider: source_chat.chat_provider,
              last_message_at: Time.current
            )
            branch_chat_messages!(source_chat, branched_chat)
          end

          render json: { id: branched_chat.id, app_path: chat_path(branched_chat) }, status: :created
        end

        # Hard-deletes a chat: the ChatSession row and every dependent
        # row (messages, bookmarks, queued messages, attachments,
        # proposals, pending actions, agent questions, wakeups,
        # whiteboard + snapshots, captured agent session) go in the
        # request transaction; the search-index rows, workspace
        # directory, and per-chat agent homes are cleaned up post-commit
        # by ChatSessionCleanupJob on the worker (the web pod doesn't
        # mount the workspace PVC). Refused while a turn is actively
        # running.
        def destroy
          chat_session = find_chat_session
          if chat_session.turn_in_flight? || chat_session.agent_busy?
            render_error(
              "turn_in_flight",
              "Cannot delete this chat while a turn is in progress. Stop the turn first.",
              status: :conflict
            )
            return
          end

          chat_session.destroy!

          render json: { message: "Chat deleted." }
        end

        def clear_messages
          chat_session = find_chat_session
          ApplicationRecord.transaction do
            chat_session.messages.destroy_all
            chat_session.chat_queued_messages.destroy_all
            chat_session.update!(last_message_at: nil, stop_requested_at: nil)
          end

          render json: chat_payload(chat_session.reload, message: "Chat history cleared.")
        end

        def mark_read
          find_chat_session.update_columns(last_read_at: Time.current)

          head :no_content
        end

        def mark_unread
          find_chat_session.update_columns(last_read_at: nil)

          head :no_content
        end

        def hide
          chat_session = find_chat_session
          chat_session.update!(hidden_at: Time.current)

          render json: { message: "Chat hidden.", chat: chat_index_json(chat_session.reload) }
        end

        def unhide
          chat_session = find_chat_session
          chat_session.update!(hidden_at: nil)

          render json: { message: "Chat restored.", chat: chat_index_json(chat_session.reload) }
        end

        def enqueue_message
          chat_session = find_chat_session
          text = message_text
          if text.blank? && !message_has_attachments?
            render_error("validation_failed", "Message cannot be blank.", status: :unprocessable_content)
            return
          end
          content = message_content(text)
          return if performed?

          queued_message = chat_session.chat_queued_messages.create!(content: content)
          chat_session.touch
          notice = "Message queued."

          unless chat_session.turn_in_flight? || chat_session.agent_busy?
            user_message = promote_queued_message(chat_session, queued_message)
            enqueue_chat_title(chat_session, user_message) if chat_session.title.blank? && user_message == first_user_message(chat_session)
            enqueue_chat_turn(chat_session, user_message)
            notice = "Message sent."
          end

          render json: chat_payload(chat_session.reload, message: notice)
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked, ActiveRecord::StatementTimeout, SolidQueue::Job::EnqueueError => e
          raise unless transient_chat_lock_error?(e)

          render_temporary_chat_lock_error
        end

        def update_queued_message
          chat_session = find_chat_session
          queued_message = chat_session.queued_messages.find(params[:queued_message_id])
          text = message_text
          existing = queued_message.content.is_a?(Hash) ? queued_message.content : {}
          if text.blank? && !queued_message.carries_media?
            render_error("validation_failed", "Message cannot be blank.", status: :unprocessable_content)
            return
          end

          # Edit only the note text; PRESERVE the media (video_walkthrough_id /
          # source / attachments) so editing a media-carrying queued message —
          # e.g. adding a note to a pending walkthrough turn — doesn't discard it
          # and silently drop the handoff on promotion.
          queued_message.update!(content: existing.merge("text" => text))
          render json: chat_payload(chat_session.reload, message: "Queued message updated.")
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        end

        def destroy_queued_message
          chat_session = find_chat_session
          queued_message = chat_session.queued_messages.find(params[:queued_message_id])
          queued_message.destroy!

          render json: chat_payload(chat_session.reload, message: "Queued message deleted.")
        end

        def create_scratchpad_item
          chat_session = find_chat_session
          content = params.dig(:scratchpad_item, :content).to_s.strip
          if content.blank?
            render_error("validation_failed", "Content cannot be blank.", status: :unprocessable_content)
            return
          end

          max_position = chat_session.scratchpad_items.maximum(:position) || -1
          chat_session.scratchpad_items.create!(content: content, position: max_position + 1)

          render json: chat_payload(chat_session.reload, message: "Scratch pad item added.")
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        end

        def update_scratchpad_item
          chat_session = find_chat_session
          item = chat_session.scratchpad_items.find(params[:item_id])
          content = params.dig(:scratchpad_item, :content).to_s.strip
          if content.blank?
            render_error("validation_failed", "Content cannot be blank.", status: :unprocessable_content)
            return
          end

          item.update!(content: content)
          render json: chat_payload(chat_session.reload, message: "Scratch pad item updated.")
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        end

        def destroy_scratchpad_item
          chat_session = find_chat_session
          item = chat_session.scratchpad_items.find(params[:item_id])
          item.destroy!

          render json: chat_payload(chat_session.reload, message: "Scratch pad item deleted.")
        end

        def reorder_scratchpad_items
          chat_session = find_chat_session
          ids = Array(params[:ids]).map { |id| Integer(id, exception: false) }.compact
          if ids.blank?
            render_error("validation_failed", "ids is required.", status: :unprocessable_content)
            return
          end

          items = chat_session.scratchpad_items.where(id: ids).index_by(&:id)
          if items.size != ids.size
            render_error("not_found", "One or more scratchpad items were not found.", status: :not_found)
            return
          end

          ids.each_with_index do |id, position|
            items[id].update_columns(position: position)
          end

          chat_session.broadcast_controls
          render json: chat_payload(chat_session.reload, message: "Scratch pad items reordered.")
        end

        def answer_agent_question
          chat_session = find_chat_session
          question = chat_session.agent_questions.find(params[:agent_question_id])
          answer = params[:answer].to_s.strip
          if answer.blank?
            render_error("validation_failed", "Answer cannot be blank.", status: :unprocessable_content)
            return
          end

          if question.answer_and_record!(answer)
            render json: chat_payload(chat_session.reload, message: "Answer submitted.")
          else
            render_error("validation_failed", "Question is no longer active.", status: :unprocessable_content)
          end
        end

        def add_attachment
          chat_session = find_chat_session
          attachable = attachable_from_params(chat_session)
          unless attachable
            render_error("validation_failed", "Choose an attachment to add.", status: :unprocessable_content)
            return
          end

          chat_session.chat_attachments.find_or_create_by!(attachable: attachable)
          render json: chat_payload(chat_session.reload, message: "#{attachment_label(attachable)} attached.")
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        end

        def destroy_attachment
          chat_session = find_chat_session
          attachment = chat_session.chat_attachments.find(params[:attachment_id])
          label = attachment_label(attachment.attachable)
          attachment.destroy!

          render json: chat_payload(chat_session.reload, message: "#{label} detached.")
        end

        def create_bookmark
          chat_session = find_chat_session
          message = params[:message_id].present? ? chat_session.messages.find(params[:message_id]) : chat_session.messages.order(:created_at, :id).last
          unless message
            render_error("validation_failed", "Cannot bookmark an empty chat.", status: :unprocessable_content)
            return
          end

          kind = params.dig(:chat_bookmark, :kind).presence_in(ChatBookmark::KINDS) || "manual"
          bookmark = message.bookmarks.create!(label: bookmark_label, kind: kind)

          render json: chat_payload(chat_session.reload, message: "Bookmarked #{bookmark.label}.")
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        end

        def confirm_pending_action
          chat_session = find_chat_session
          pending_action = find_pending_action(chat_session)

          if pending_action.confirm!(user: Current.user)
            render json: chat_payload(chat_session.reload, message: pending_action_confirmed_notice(pending_action))
          else
            render_error("validation_failed", "Pending action is no longer active.", status: :unprocessable_content)
          end
        rescue ActiveRecord::RecordInvalid => e
          message = e.record.errors.full_messages.to_sentence.presence || "Pending action could not be confirmed."
          render_error("validation_failed", message, status: :unprocessable_content)
        rescue ArgumentError => e
          render_error("validation_failed", e.message, status: :unprocessable_content)
        end

        def destroy_pending_action
          chat_session = find_chat_session
          pending_action = find_pending_action(chat_session)
          rejection = pending_action.action_type != "schedule_recurring" && !pending_action.queued?
          result = rejection ? pending_action.reject! : pending_action.cancel!(user: Current.user)

          if result
            render json: chat_payload(chat_session.reload, message: rejection ? "Pending action rejected." : "Pending action cancelled.")
          else
            render_error("validation_failed", "Pending action is no longer active.", status: :unprocessable_content)
          end
        end

        def confirm_proposal
          chat_session = find_chat_session
          proposal = find_proposal(chat_session)
          if proposal.confirmed?
            render_error("validation_failed", "Proposal is already confirmed.", status: :unprocessable_content)
            return
          end

          unless proposal.proposed?
            render_error("validation_failed", "Proposal is no longer proposed.", status: :unprocessable_content)
            return
          end

          if product_owner_proposal_adds_jobs_to_epics?(proposal)
            render_error("forbidden", PRODUCT_OWNER_EPIC_JOB_MESSAGE, status: :forbidden)
            return
          end

          result = if proposal.epic_bundle?
            ChatEpicProposalMaterializer.new(user: Current.user).file!(proposal)
          else
            ChatProposalFiler.new(user: Current.user, repository: proposal.effective_repository).file!([ proposal ])
          end
          epic_started = maybe_start_confirmed_epic!(proposal, result)

          confirmation_message = chat_session.messages.create!(
            role: "system",
            content: proposal_outcome_control_content(
              proposal.reload,
              text: proposal_confirmation_text(proposal, result, epic_started: epic_started),
              outcome: :confirmed
            )
          )
          notify_agent_of_proposal_outcome(confirmation_message)
          broadcast_proposal_updated(chat_session, proposal.reload)

          render json: chat_payload(chat_session.reload, message: proposal_confirmed_notice(proposal, result, epic_started: epic_started))
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        rescue ArgumentError => e
          render_error("validation_failed", e.message, status: :unprocessable_content)
        end

        def reject_proposal
          chat_session = find_chat_session
          proposal = find_proposal(chat_session)

          if proposal.proposed?
            proposal.transaction do
              now = Time.current
              proposal.update!(state: "rejected", rejected_at: now)
              proposal.child_proposals.where(state: "proposed").update_all(
                state: "rejected",
                rejected_at: now
              )
            end
            rejection_message = chat_session.messages.create!(
              role: "system",
              content: proposal_outcome_control_content(
                proposal,
                text: proposal_rejection_text(proposal),
                outcome: :rejected
              )
            )
            notify_agent_of_proposal_outcome(rejection_message)
            broadcast_proposal_updated(chat_session, proposal.reload)
            render json: chat_payload(chat_session.reload, message: "Proposal rejected.")
          else
            render_error("validation_failed", "Proposal is no longer proposed.", status: :unprocessable_content)
          end
        end

        def update_proposal
          chat_session = find_chat_session
          proposal = find_proposal(chat_session)

          unless proposal.proposed?
            render_error("validation_failed", "Proposal is no longer proposed.", status: :unprocessable_content)
            return
          end

          attrs = proposal_update_params
          ApplicationRecord.transaction do
            depends_on_job_ids = dependency_ids!(Current.user.jobs, Array(attrs[:depends_on_job_ids]), "depends_on_job_ids")
            depends_on_epic_ids = dependency_ids!(Current.user.epics, Array(attrs[:depends_on_epic_ids]), "depends_on_epic_ids")
            proposal.update!(
              title: attrs[:title],
              body: attrs[:body],
              depends_on_job_ids: depends_on_job_ids,
              depends_on_epic_ids: depends_on_epic_ids
            )
            rebuild_proposal_dependencies!(chat_session, proposal, Array(attrs[:dependency_slugs]))
            proposal.reset_to_proposed_after_edit!
          end

          broadcast_proposal_updated(chat_session, proposal.reload)
          render json: chat_payload(chat_session.reload, message: "Proposal updated.").merge(
            proposal: ::App::ChatMessagePayload.proposal(proposal, chat_session: chat_session, repository: chat_session.repository)
          )
        rescue ActiveRecord::RecordInvalid => e
          render_error("validation_failed", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        rescue ArgumentError => e
          render_error("validation_failed", e.message, status: :unprocessable_content)
        end

        def cancel_coding_checkout
          chat_session = find_chat_session
          unless Feature.coding_mode_enabled?
            render_error("feature_disabled", "Coding Mode is not enabled on this instance.", status: :not_found)
            return
          end

          repository = chat_session.repository
          unless repository
            render_error("not_found", "No repository attached to this chat.", status: :not_found)
            return
          end

          if chat_session.coding_checkout_branch.blank?
            render_error("not_found", "No active coding checkout for this chat.", status: :not_found)
            return
          end

          ChatWorkspace.cancel_coding_checkout!(chat_session, repository)
          render json: chat_payload(chat_session.reload, message: "Coding checkout cancelled.")
        rescue ActiveRecord::RecordNotFound
          raise
        rescue StandardError => e
          render_error("server_error", "Could not cancel coding checkout: #{e.message}", status: :internal_server_error)
        end

        def coding_files
          chat_session = find_chat_session
          unless Feature.coding_mode_enabled?
            render_error("feature_disabled", "Coding Mode is not enabled on this instance.", status: :not_found)
            return
          end

          unless chat_session.repository
            render_error("not_found", "No repository attached to this chat.", status: :not_found)
            return
          end

          if chat_session.coding_checkout_branch.blank?
            render_error("not_found", "No active coding checkout for this chat.", status: :not_found)
            return
          end

          result = ChatWorkspace.file_tree(chat_session, chat_session.repository)
          unless result
            render_error("not_found", "Coding checkout directory not found.", status: :not_found)
            return
          end

          render json: result
        end

        def coding_file
          chat_session = find_chat_session
          unless Feature.coding_mode_enabled?
            render_error("feature_disabled", "Coding Mode is not enabled on this instance.", status: :not_found)
            return
          end

          unless chat_session.repository
            render_error("not_found", "No repository attached to this chat.", status: :not_found)
            return
          end

          if chat_session.coding_checkout_branch.blank?
            render_error("not_found", "No active coding checkout for this chat.", status: :not_found)
            return
          end

          file_path = params[:path].to_s.strip
          if file_path.blank?
            render_error("validation_failed", "path parameter is required.", status: :unprocessable_content)
            return
          end

          result = ChatWorkspace.file_content(chat_session, chat_session.repository, file_path)
          if result.nil?
            render_error("not_found", "File not found in coding checkout.", status: :not_found)
            return
          end

          render json: result.merge(path: file_path)
        end

        def coding_diff
          chat_session = find_chat_session
          unless Feature.coding_mode_enabled?
            render_error("feature_disabled", "Coding Mode is not enabled on this instance.", status: :not_found)
            return
          end

          unless chat_session.repository
            render json: { diff: "", mode: "cumulative", checkout_branch: nil }
            return
          end

          mode = params[:mode].to_s == "turn" ? :turn : :cumulative
          diff = ChatWorkspace.coding_diff(chat_session, chat_session.repository, mode: mode)

          render json: {
            diff: diff,
            mode: mode.to_s,
            checkout_branch: chat_session.coding_checkout_branch
          }
        end

        def search_proposals
          chat_session = find_chat_session
          query = params[:q].to_s.strip
          scope = chat_session.proposals
          scope = scope.where.not(id: params[:exclude_id]) if params[:exclude_id].present?
          if query.present?
            pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
            scope = scope.where("LOWER(title) LIKE :pattern OR LOWER(slug) LIKE :pattern", pattern: pattern)
          end

          render json: {
            proposals: scope.order(:created_at, :id).limit(10).map { |proposal| proposal_search_json(proposal) }
          }
        end

        private

        def search_payload_for_query(scope, query, page)
          allowed_session_ids = scope.distinct.pluck(:id).map(&:to_i)
          grouped_matches = []
          matches_by_chat = {}

          chat_search_rows(query).each do |row|
            chat_session_id = row.fetch(:chat_session_id).to_i
            next unless allowed_session_ids.include?(chat_session_id)

            grouped_matches << chat_session_id unless matches_by_chat.key?(chat_session_id)
            matches_by_chat[chat_session_id] ||= []
            matches_by_chat[chat_session_id] << row
          end

          total = grouped_matches.length
          paged_chat_ids = grouped_matches.slice(search_offset(page), SEARCH_PAGE_SIZE) || []
          sessions_by_id = Current.user.chat_sessions
            .where(id: paged_chat_ids)
            .preload(repository_attachments: :attachable)
            .index_by(&:id)

          {
            results: paged_chat_ids.filter_map do |chat_session_id|
              chat_search_result_json(sessions_by_id[chat_session_id], matches_by_chat.fetch(chat_session_id))
            end,
            total: total,
            page: page,
            per_page: SEARCH_PAGE_SIZE
          }
        end

        def search_payload_for_scope(scope, page)
          total = scope.distinct.count
          sessions = scope
            .distinct
            .preload(repository_attachments: :attachable)
            .order(updated_at: :desc, id: :desc)
            .offset(search_offset(page))
            .limit(SEARCH_PAGE_SIZE)

          {
            results: sessions.map { |chat_session| chat_filter_result_json(chat_session) },
            total: total,
            page: page,
            per_page: SEARCH_PAGE_SIZE
          }
        end

        def filtered_chat_search_scope
          scope = ChatSession.where(user_id: Current.user.id).visible
          scope = apply_chat_attachment_filter(scope, "Repository", :repository_id)
          return scope if performed?

          scope = apply_chat_attachment_filter(scope, "Epic", :epic_id)
          return scope if performed?

          apply_chat_attachment_filter(scope, "Job", :job_id)
        end

        def apply_chat_attachment_filter(scope, attachable_type, param_name)
          attachable_id = optional_positive_integer_param(param_name)
          return scope unless attachable_id

          alias_name = "chat_attachments_#{param_name}_filter"
          quoted_alias = ApplicationRecord.connection.quote_table_name(alias_name)
          quoted_type = ApplicationRecord.connection.quote(attachable_type)

          scope.joins(<<~SQL.squish)
            INNER JOIN chat_attachments #{quoted_alias}
              ON #{quoted_alias}.chat_session_id = chat_sessions.id
              AND #{quoted_alias}.attachable_type = #{quoted_type}
              AND #{quoted_alias}.attachable_id = #{attachable_id}
          SQL
        end

        def optional_positive_integer_param(name)
          raw = params[name]
          return if raw.blank?

          value = Integer(raw, exception: false)
          return value if value&.positive?

          render_error("bad_request", "#{name} must be a positive integer.", status: :bad_request)
          nil
        end

        def search_query
          params[:q].to_s.strip
        end

        def proposal_update_params
          params.require(:proposal).permit(:title, :body, dependency_slugs: [], depends_on_job_ids: [], depends_on_epic_ids: [])
        end

        def rebuild_proposal_dependencies!(chat_session, proposal, dependency_slugs)
          slugs = dependency_slugs.map(&:to_s).map(&:strip).reject(&:blank?).uniq
          dependencies = chat_session.proposals.where(slug: slugs).index_by(&:slug)
          missing = slugs - dependencies.keys
          raise ArgumentError, "Unknown proposal dependency: #{missing.first}" if missing.any?

          proposal.dependency_edges.destroy_all
          slugs.each do |slug|
            proposal.dependency_edges.create!(depends_on: dependencies.fetch(slug))
          end
        end

        def dependency_ids!(scope, raw_ids, name)
          ids = raw_ids.map(&:to_i).select(&:positive?).uniq
          found_ids = scope.where(id: ids).pluck(:id)
          missing = ids - found_ids
          raise ArgumentError, "Unknown #{name}: #{missing.first}" if missing.any?

          ids
        end

        def proposal_search_json(proposal)
          {
            id: proposal.id,
            slug: proposal.slug,
            title: proposal.title,
            state: proposal.state
          }
        end

        def broadcast_proposal_updated(chat_session, proposal)
          AppEvents.broadcast(
            user: chat_session.user,
            type: "updated",
            resource: "chat",
            id: chat_session.id,
            changed: [ "proposal" ],
            payload: {
              action: "update_proposal",
              proposal_id: proposal.id
            }
          )
        end

        def search_page
          [ Integer(params[:page], exception: false).to_i, 1 ].max
        end

        def search_offset(page)
          (page - 1) * SEARCH_PAGE_SIZE
        end

        def chat_search_rows(query, chat_session_id: nil)
          ChatMessageSearchIndex.search(
            query,
            user_id: Current.user.id,
            chat_session_id: chat_session_id,
            limit: nil,
            snippet_start: "<b>",
            snippet_end: "</b>",
            snippet_tokens: 50
          )
        end

        def chat_search_result_json(chat_session, rows)
          return unless chat_session

          top_matches = rows.first(SEARCH_TOP_MATCHES).map { |row| chat_search_match_json(row) }
          {
            chat_session_id: chat_session.id,
            chat_title: chat_search_title(chat_session),
            best_snippet: top_matches.first&.fetch(:snippet),
            best_match_message_id: top_matches.first&.fetch(:message_id),
            top_matches: top_matches,
            total_match_count: rows.length,
            has_more_matches: rows.length > SEARCH_TOP_MATCHES
          }
        end

        def chat_filter_result_json(chat_session)
          {
            chat_session_id: chat_session.id,
            chat_title: chat_search_title(chat_session),
            best_snippet: nil,
            best_match_message_id: nil,
            top_matches: [],
            total_match_count: 0,
            has_more_matches: false
          }
        end

        def chat_search_match_json(row)
          {
            message_id: row.fetch(:chat_message_id).to_i,
            role: row.fetch(:role),
            snippet: row.fetch(:snippet),
            created_at: row.fetch(:created_at)
          }
        end

        def chat_search_title(chat_session)
          chat_session.title.presence || ChatSession.fallback_title_for(chat_session.repository)
        end

        # Walkthrough videos shared in this chat, for the workspace media panel.
        # Metadata only — the video itself is far too large to inline (unlike the
        # base64 image attachments) and is pruned after a retention window, so
        # `has_video` tells the UI whether it can still be played back / re-analyzed.
        def video_walkthroughs_json(chat_session)
          chat_session.video_walkthroughs.newest_first.map do |walkthrough|
            {
              id: walkthrough.id,
              title: walkthrough.display_title,
              state: walkthrough.state,
              duration_seconds: walkthrough.duration_seconds,
              byte_size: walkthrough.byte_size,
              error_message: walkthrough.error_message,
              has_video: walkthrough.file.attached?,
              created_at: walkthrough.created_at.iso8601
            }
          end
        end

        def chat_payload(chat_session, message: nil)
          messages, has_more_older = paginated_tail(chat_session)
          repository = chat_session.repository
          attachment_groups = chat_session.chat_attachments.includes(:attachable).order(:attachable_type, :attached_at, :id).group_by(&:attachable_type)
          whiteboard = chat_session.whiteboard
          whiteboard_scene = whiteboard ? whiteboard.current_state : Whiteboard.default_state

          {
            message: message,
            chat: chat_json(chat_session),
            chat_available: Current.user.chat_available?,
            turn_in_flight: chat_session.turn_in_flight?,
            agent_busy: chat_session.agent_busy?,
            switching_provider: false,
            has_more_older: has_more_older,
            messages: messages_json(messages, repository: repository),
            bookmarks: chat_session.bookmarks.includes(:chat_message).map { |bookmark| bookmark_json(bookmark) },
            recent_chats: recent_chats_json(chat_session),
            pending_actions: pending_actions_json(chat_session),
            agent_questions: chat_session.agent_questions_payload,
            queued_messages: chat_session.queued_messages_payload,
            scratchpad_items: chat_session.scratchpad_items_payload,
            video_walkthroughs: video_walkthroughs_json(chat_session),
            attachment_groups: attachment_groups_json(attachment_groups),
            documents_in_scope: chat_session.attached_documents_in_scope.includes(:attachable).order(:title, :id).map { |document| document_json(document) },
            attachment_results: attachment_search_results(chat_session).map { |record| attachable_result_json(record) },
            whiteboard: {
              version: whiteboard_scene.fetch("version"),
              elements: whiteboard_scene.fetch("elements"),
              appState: whiteboard_scene.fetch("appState"),
              files: whiteboard_scene.fetch("files")
            },
            paths: {
              credentials_path: "/credentials",
              repositories_path: repositories_path,
              app_messages_path: "/api/v1/app/chats/#{chat_session.id}/messages",
              app_message_path: "/api/v1/app/chats/#{chat_session.id}/message",
              app_rename_path: "/api/v1/app/chats/#{chat_session.id}/rename",
              app_delete_path: "/api/v1/app/chats/#{chat_session.id}",
              app_clear_path: "/api/v1/app/chats/#{chat_session.id}/messages",
              app_branch_path: "/api/v1/app/chats/#{chat_session.id}/branch",
              app_share_path: "/api/v1/app/chats/#{chat_session.id}/share",
              app_enqueue_message_path: "/api/v1/app/chats/#{chat_session.id}/queued_messages",
              app_stop_path: "/api/v1/app/chats/#{chat_session.id}/stop",
              app_daemon_connection_path: "/api/v1/app/chats/#{chat_session.id}/daemon_connection",
              app_bookmarks_path: "/api/v1/app/chats/#{chat_session.id}/bookmarks",
              app_attachments_path: "/api/v1/app/chats/#{chat_session.id}/attachments",
              app_whiteboard_path: "/api/v1/app/chats/#{chat_session.id}/whiteboard",
              app_switch_provider_path: "/api/v1/app/chats/#{chat_session.id}/switch_provider",
              app_scratchpad_reorder_path: "/api/v1/app/chats/#{chat_session.id}/scratchpad_items/reorder",
              app_video_walkthroughs_path: "/api/v1/app/chats/#{chat_session.id}/video_walkthroughs",
              app_cancel_coding_checkout_path: "/api/v1/app/chats/#{chat_session.id}/coding_checkout",
              app_coding_files_path: "/api/v1/app/chats/#{chat_session.id}/coding_files",
              app_coding_file_path: "/api/v1/app/chats/#{chat_session.id}/coding_file",
              app_coding_diff_path: "/api/v1/app/chats/#{chat_session.id}/coding_diff"
            },
            gemini_configured: Current.user.gemini_configured?,
            # Labs flag: gates the composer's record/drag/upload intake. The
            # video_walkthroughs media list stays in the payload regardless so
            # already-analyzed threads keep their history when the flag is off.
            walkthroughs_enabled: Feature.video_walkthroughs_enabled?,
            coding_mode_enabled: Feature.coding_mode_enabled?,
            local_mode_enabled: Feature.local_mode_enabled?,
            local_tunnel_connected: Feature.local_mode_enabled? && LocalDaemonSession.connected.exists?(chat_session_id: chat_session.id)
          }
        end

        def paginated_tail(chat_session)
          scope = message_scope(chat_session)
          fetched = scope.order(id: :desc).limit(PAGE_SIZE + 1).to_a
          has_more = fetched.size > PAGE_SIZE
          [ fetched.first(PAGE_SIZE).reverse, has_more ]
        end

        def paginated_before(chat_session, before_id)
          scope = message_scope(chat_session)
          scope = scope.where("id < ?", before_id) if before_id&.positive?
          fetched = scope.order(id: :desc).limit(PAGE_SIZE + 1).to_a
          has_more = fetched.size > PAGE_SIZE
          [ fetched.first(PAGE_SIZE).reverse, has_more ]
        end

        def message_scope(chat_session)
          scope = ChatMessage.where(chat_session_id: chat_session.id)
          scope = force_chat_message_cursor_index(scope) if mysql_adapter?

          scope.includes(:pending_action, proposal: [ :repository, :job, :epic, :target_epic, dependencies: [], child_proposals: [ :repository, :job, dependencies: [] ] ])
        end

        def force_chat_message_cursor_index(scope)
          scope.from(Arel.sql("#{ChatMessage.quoted_table_name} FORCE INDEX (index_chat_messages_on_session_id_and_id)"))
        end

        def mysql_adapter?
          ActiveRecord::Base.connection.adapter_name.downcase.include?("mysql")
        end

        def messages_json(messages, repository:)
          ::App::ChatMessagePayload.messages(messages, repository: repository)
        end

        def bookmark_json(bookmark)
          {
            id: bookmark.id,
            label: bookmark.label,
            chat_message_id: bookmark.chat_message_id,
            anchor_message_id: bookmark.anchor_message_id
          }
        end

        def hidden_chat_json(chat_session)
          chat_index_json(chat_session).merge(
            hidden_at: chat_session.hidden_at&.iso8601,
            app_unhide_path: "/api/v1/app/chats/#{chat_session.id}/unhide"
          )
        end

        def chat_unread?(chat_session)
          chat_session.last_message_at.present? &&
            (chat_session.last_read_at.blank? || chat_session.last_message_at > chat_session.last_read_at)
        end

        def pending_actions_json(chat_session)
          chat_session.pending_actions.where(state: %w[queued pending]).order(:created_at, :id).map do |action|
            {
              id: action.id,
              label: pending_action_label(action),
              detail: pending_action_detail(action),
              state: action.state,
              action: action.action,
              action_type: action.action_type,
              chat_message_id: action.message&.id,
              app_confirm_path: "/api/v1/app/chats/#{chat_session.id}/pending_actions/#{action.id}/confirm",
              app_reject_path: "/api/v1/app/chats/#{chat_session.id}/pending_actions/#{action.id}/reject",
              app_cancel_path: "/api/v1/app/chats/#{chat_session.id}/pending_actions/#{action.id}"
            }
          end
        end

        def attachment_groups_json(groups)
          {
            repositories: attachment_group_json(groups["Repository"]),
            epics: attachment_group_json(groups["Epic"]),
            jobs: attachment_group_json(groups["Job"]),
            documents: attachment_group_json(groups["Document"])
          }
        end

        def attachment_group_json(attachments)
          Array(attachments).map do |attachment|
            {
              id: attachment.id,
              label: attachment_label(attachment.attachable),
              app_detach_path: "/api/v1/app/chats/#{attachment.chat_session_id}/attachments/#{attachment.id}"
            }
          end
        end

        def document_json(document)
          {
            id: document.id,
            title: document.title,
            repository_slug: document.repository&.slug
          }
        end

        ATTACHMENT_LABEL_FORMATTERS = {
          Repository => ->(r) { r.slug },
          Epic       => ->(r) { [ r.slug, r.title.presence ].compact.join(": ") },
          Job        => ->(r) { "#{r.slug}: #{r.issue_title.presence || r.issue_number || r.kind}" },
          Document   => ->(r) { "#{r.title} (#{r.repository&.slug})" }
        }.freeze

        def create_chat_session
          text = message_text
          repository = repository_from_params
          content = message_content(text) if text.present?
          return if performed?

          chat_session = nil
          user_message = nil

          ApplicationRecord.transaction do
            chat_session = ChatSession.create!(
              user: Current.user,
              repository: repository,
              title: nil,
              last_message_at: text.present? ? Time.current : nil
            )
            if text.present?
              user_message = chat_session.messages.create!(role: "user", content: content)
            end
          end

          enqueue_chat_title(chat_session, user_message) if user_message
          enqueue_chat_turn(chat_session, user_message) if user_message
          chat_session
        end

        def enqueue_chat_title(chat_session, user_message)
          ChatTitleJob.perform_later(chat_session.id, user_message.id)
        end

        def first_user_message(chat_session)
          chat_session.messages.where(role: "user").order(:created_at, :id).first
        end

        def enqueue_chat_turn(chat_session, user_message)
          retry_delays = CHAT_TURN_ENQUEUE_RETRY_DELAYS.dup

          begin
            ChatTurnJob.perform_later(chat_session.id, user_message.id)
          rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked, ActiveRecord::StatementTimeout, SolidQueue::Job::EnqueueError => e
            raise unless transient_chat_lock_error?(e) && retry_delays.any?

            delay = retry_delays.shift
            Rails.logger.warn("Retrying ChatTurnJob enqueue after transient database lock: #{e.class}: #{e.message}")
            sleep(delay) if delay.positive?
            retry
          end
        end

        def notify_agent_of_proposal_outcome(message)
          chat_session = message.chat_session
          return unless chat_session

          ApplicationRecord.transaction do
            chat_session.update!(
              last_message_at: Time.current,
              title: chat_session.title.presence
            )
          end

          enqueue_chat_turn(chat_session, message)
        end

        def proposal_outcome_control_content(proposal, text:, outcome:)
          {
            "text" => text,
            "source" => ChatProposalOutcomeNotification::SOURCE,
            "outcome" => outcome.to_s,
            "acknowledgment" => ChatProposalOutcomeNotification.acknowledgment(proposal, outcome: outcome)
          }
        end

        def promote_queued_message(chat_session, queued_message)
          user_message = nil
          ApplicationRecord.transaction do
            locked_chat = ChatSession.lock.find(chat_session.id)
            locked_queued_message = locked_chat.queued_messages.find(queued_message.id)
            user_message = locked_chat.messages.create!(role: "user", content: locked_queued_message.content)
            locked_queued_message.update!(delivered_at: Time.current)
            locked_chat.update!(
              last_message_at: Time.current,
              title: locked_chat.title.presence
            )
          end
          user_message
        end

        def render_temporary_chat_lock_error
          render_error(
            "temporary_lock",
            "Chat request was blocked by a temporary database lock. Try again.",
            status: :service_unavailable
          )
        end

        def transient_chat_lock_error?(error)
          error_chain(error).any? do |candidate|
            candidate.is_a?(ActiveRecord::LockWaitTimeout) ||
              candidate.is_a?(ActiveRecord::Deadlocked) ||
              candidate.is_a?(ActiveRecord::StatementTimeout) ||
              candidate.class.name == "SQLite3::BusyException" ||
              candidate.message.match?(/SQLite3::BusyException|database is locked|LockWaitTimeout|Deadlocked|StatementTimeout/i)
          end
        end

        def error_chain(error)
          chain = []
          while error && !chain.include?(error)
            chain << error
            error = error.cause
          end
          chain
        end

        def find_chat_session
          Current.user.chat_sessions.find(params[:id])
        end

        BRANCH_TITLE_SUFFIX = " (branch)".freeze

        # Rename enforces ChatSession::TITLE_MAX_LENGTH (in characters,
        # matching the model validation), so a branch of a max-length
        # title must clamp the base before appending the suffix instead
        # of overflowing it.
        def branch_chat_title(source_chat)
          base = source_chat.title.presence ||
            ChatSession.fallback_title_for(source_chat.repository).presence ||
            "New chat"
          max_base_length = ChatSession::TITLE_MAX_LENGTH - BRANCH_TITLE_SUFFIX.length
          base = base.truncate(max_base_length, omission: "…") if base.length > max_base_length
          "#{base}#{BRANCH_TITLE_SUFFIX}"
        end

        def find_branch_source_chat_session
          chat_session = ChatSession.find(params[:id])
          return chat_session if chat_session.user_id == Current.user.id

          render_error("forbidden", "You cannot branch this chat.", status: :forbidden)
          nil
        end

        def branch_chat_messages!(source_chat, branched_chat)
          rows = source_chat.messages.order(:created_at, :id).map do |message|
            message.attributes.slice(
              "role",
              "content",
              "tool_name",
              "tool_use_id",
              "created_at",
              "updated_at"
            ).merge(
              "chat_session_id" => branched_chat.id,
              "proposal_id" => nil,
              "pending_action_id" => nil
            )
          end
          ChatMessage.insert_all!(rows) if rows.any?
        end

        def find_pending_action(chat_session)
          chat_session.pending_actions.find(params[:pending_action_id])
        end

        def find_proposal(chat_session)
          chat_session.proposals.find(params[:proposal_id])
        end

        def product_owner_proposal_adds_jobs_to_epics?(proposal)
          return false unless Current.user.product_owner?

          if proposal.epic_bundle?
            return proposal.child_proposals.where(state: "proposed").exists?
          end

          ChatProposalFiler.ordered_closure([ proposal ]).any? do |candidate|
            candidate.proposed? &&
              candidate.target_epic_id.present? &&
              (candidate.syrus_issue? || candidate.job?)
          end
        end

        def message_text
          (params[:content].presence || params.dig(:chat_message, :text)).to_s.strip
        end

        # A message may carry media (image/PDF attachments) with no text — the
        # media is the message. The blank-text guard uses this to allow that.
        def message_has_attachments?
          params.dig(:chat_message, :attachments).present?
        end

        def message_content(text)
          content = { "text" => text }
          attachments = params.dig(:chat_message, :attachments)
          return content if attachments.blank?

          sanitized = sanitized_attachments(attachments)
          return if performed?

          content["attachments"] = sanitized
          content
        end

        def sanitized_attachments(attachments)
          unless attachments.is_a?(Array)
            render_error("validation_failed", "Attachments must be an array.", status: :unprocessable_content)
            return
          end

          attachments.map do |attachment|
            attributes = attachment.respond_to?(:to_unsafe_h) ? attachment.to_unsafe_h : attachment
            unless attributes.respond_to?(:[])
              render_error("validation_failed", "Attachments must be objects.", status: :unprocessable_content)
              return
            end

            name = attributes["name"] || attributes[:name]
            mime_type = (attributes["mime_type"] || attributes[:mime_type]).to_s
            data = (attributes["data"] || attributes[:data]).to_s

            unless CHAT_ATTACHMENT_ALLOWED_MIME_TYPES.include?(mime_type)
              render_error("validation_failed", "Attachment MIME type is not allowed.", status: :unprocessable_content)
              return
            end

            if data.bytesize > CHAT_ATTACHMENT_MAX_BASE64_BYTES
              render_error("validation_failed", "Attachment data must be 7 MB or smaller.", status: :unprocessable_content)
              return
            end

            { "name" => name.to_s, "mime_type" => mime_type, "data" => data }
          end
        end

        def chat_name
          (params[:name].presence || params.dig(:chat, :name).presence || params.dig(:chat, :title)).to_s.strip
        end

        def stream_request?
          request.format == Mime[:event_stream] || request.headers["Accept"].to_s.include?("text/event-stream")
        end

        def stream_chat_turn(chat_session, user_message)
          response.headers["Content-Type"] = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["X-Accel-Buffering"] = "no"

          self.response_body = Enumerator.new do |stream|
            write_sse(stream, "message", { role: "user", content: user_message.content["text"].to_s, message: chat_message_json(user_message, chat_session: chat_session) })
            stream_chat_messages(stream, chat_session, after_id: user_message.id)
          rescue StandardError => e
            write_sse(stream, "error", { message: e.message })
          end
        end

        def stream_chat_messages(stream, chat_session, after_id:)
          deadline = Time.current + CHAT_STREAM_TIMEOUT
          last_seen_id = after_id
          observed_turn_response = false

          loop do
            messages = chat_session.messages
              .includes(:pending_action, proposal: [ :repository, :job, :epic, :target_epic, dependencies: [], child_proposals: [ :repository, dependencies: [] ] ])
              .where("id > ?", last_seen_id)
              .order(:id)
              .to_a

            messages.each do |message|
              last_seen_id = message.id
              next if message.role == "user"

              observed_turn_response = true
              write_chat_stream_message(stream, message, chat_session: chat_session)
            end

            chat_session.reload
            if observed_turn_response && !chat_session.turn_in_flight? && !chat_session.agent_busy?
              write_sse(stream, "turn_complete", { chat_id: chat_session.id })
              break
            end

            if Time.current >= deadline
              write_sse(stream, "error", { message: "Chat turn timed out while waiting for the agent response." })
              break
            end

            sleep CHAT_STREAM_POLL_INTERVAL
          end
        end

        def write_chat_stream_message(stream, message, chat_session:)
          payload = chat_message_json(message, chat_session: chat_session)
          case message.role
          when "assistant"
            write_sse(stream, "text_chunk", { content: payload[:text], message: payload })
            write_sse(stream, "proposal", { proposal: payload[:proposal], message: payload }) if payload[:proposal]
          when "system"
            write_sse(stream, "error", { message: payload[:text], message_record: payload })
          else
            write_sse(stream, "message", { message: payload })
          end
        end

        def chat_message_json(message, chat_session:)
          ::App::ChatMessagePayload.messages([ message ], repository: chat_session.repository).first
        end

        def write_sse(stream, event, data)
          stream << "event: #{event}\n"
          stream << "data: #{JSON.generate(data)}\n\n"
        end

        def bookmark_label
          params.dig(:chat_bookmark, :label).to_s.strip
        end

        def chat_json(chat_session)
          repository = chat_session.repository
          {
            id: chat_session.id,
            title: chat_session.title.presence || ChatSession.fallback_title_for(repository),
            title_pending: chat_session.title_pending?,
            pinned: chat_session.pinned?,
            pinned_context: chat_session.pinned_context,
            chat_provider: chat_session.chat_provider,
            effective_chat_provider: chat_session.effective_chat_provider,
            effective_chat_provider_label: chat_provider_label(chat_session.effective_chat_provider),
            chat_provider_options: chat_provider_options(chat_session),
            mode: chat_session.mode,
            local_daemon_state: chat_session.local_daemon_state,
            local_daemon_repo: chat_session.local_daemon_repo,
            local_daemon_branch: chat_session.local_daemon_branch,
            chat_path: chat_path(chat_session),
            repository: repository ? repository_json(repository).merge(repository_path: repository_path(repository)) : nil,
            turn_in_flight: chat_session.turn_in_flight?,
            agent_busy: chat_session.agent_busy?,
            stop_requested_at: chat_session.stop_requested_at&.iso8601,
            suggested_next_step: chat_session.suggested_next_step,
            cumulative_input_tokens: chat_session.cumulative_input_tokens.to_i,
            cumulative_output_tokens: chat_session.cumulative_output_tokens.to_i,
            cumulative_cost_usd: chat_session.cumulative_cost.to_f,
            pending_proposal_count: chat_session.proposals.where(state: "proposed").count +
              chat_session.pending_actions.where(state: "pending").count,
            confirmed_proposal_count: chat_session.proposals.confirmed.count,
            linked_direct_job_count: Job.where(linked_chat_id: chat_session.id, kind: "direct").count,
            scratchpad_items_count: chat_session.scratchpad_items.count,
            coding_checkout_uncommitted: chat_session.coding_checkout_uncommitted?,
            coding_checkout_branch: chat_session.coding_checkout_branch
          }
        end

        def request_chat_agent_kill!(chat_session)
          SpawnedProcess.running
                        .where(kind: "agent", workdir: chat_session.workspace_root.to_s)
                        .find_each { |process| process.request_kill!(user: Current.user) }
        end

        def repository_json(repository)
          {
            id: repository.id,
            slug: repository.slug
          }
        end

        def attachment_label(record)
          formatter = ATTACHMENT_LABEL_FORMATTERS[record.class]
          formatter ? formatter.call(record) : record.try(:name).presence || record.try(:title).presence || "#{record.class.name} ##{record.id}"
        end

      end
    end
  end
end
