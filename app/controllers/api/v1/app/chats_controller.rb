module Api
  module V1
    module App
      class ChatsController < BaseController
        PAGE_SIZE = ::ChatsController::PAGE_SIZE
        SYSTEM_RESULT_PATTERN = /\A\[(?:codex )?result\]\s+(?<payload>.+)\z/
        SYSTEM_MCP_PATTERN = /\A\[mcp_servers\]\s+(?<payload>.+)\z/
        SYSTEM_CODEX_ERROR_PATTERN = /\A\[codex error\]\s+(?<message>.+)\z/

        def new
          render json: form_payload
        end

        def show
          render json: chat_payload(find_chat_session)
        end

        def messages
          chat_session = find_chat_session
          before_id = Integer(params[:before], exception: false)
          messages, has_more_older = paginated_before(chat_session, before_id)

          render json: {
            has_more_older: has_more_older,
            messages: grouped_messages_json(messages, repository: chat_session.repository)
          }
        end

        def create
          chat_session = create_chat_session

          render json: {
            message: chat_session.messages.exists? ? "Message sent." : "Chat created.",
            redirect_to: chat_path(chat_session),
            chat: chat_json(chat_session)
          }, status: :created
        rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
          render_error(
            "temporary_lock",
            "Chat creation was blocked by a temporary database lock. Try again.",
            status: :service_unavailable
          )
        end

        def message
          chat_session = find_chat_session
          text = message_text
          if text.blank?
            render_error("validation_failed", "Message cannot be blank.", status: :unprocessable_content)
            return
          end

          user_message = nil
          ApplicationRecord.transaction do
            chat_session.update!(last_message_at: Time.current, title: chat_session.title.presence || text.truncate(80))
            user_message = chat_session.messages.create!(role: "user", content: { "text" => text })
          end
          ChatTurnJob.perform_later(chat_session.id, user_message.id)

          render json: chat_payload(chat_session.reload, message: "Message sent.")
        end

        def stop
          chat_session = find_chat_session
          chat_session.update!(stop_requested_at: Time.current)
          chat_session.broadcast_controls

          render json: chat_payload(chat_session.reload, message: "Stop requested.")
        end

        def refresh
          chat_session = find_chat_session
          unless chat_session.repository
            render_error("validation_failed", "Attach a repository before refreshing a workspace.", status: :unprocessable_content)
            return
          end

          ChatWorkspaceJob.perform_later(chat_session.id, action: :refresh)
          render json: chat_payload(chat_session.reload, message: "Repository refresh queued.")
        end

        def reset
          chat_session = find_chat_session
          unless chat_session.repository
            render_error("validation_failed", "Attach a repository before resetting a workspace.", status: :unprocessable_content)
            return
          end

          ChatWorkspaceJob.perform_later(chat_session.id, action: :reset)
          render json: chat_payload(chat_session.reload, message: "Workspace reset queued.")
        end

        private

        def form_payload
          {
            repositories: Current.user.repositories.active.order(:owner, :name).map { |repository| repository_json(repository) },
            repositories_path: repositories_path
          }
        end

        def chat_payload(chat_session, message: nil)
          messages, has_more_older = paginated_tail(chat_session)
          repository = chat_session.repository
          attachment_groups = chat_session.chat_attachments.includes(:attachable).order(:attachable_type, :attached_at, :id).group_by(&:attachable_type)
          whiteboard = chat_session.whiteboard

          {
            message: message,
            chat: chat_json(chat_session),
            chat_available: Current.user.claude_oauth_token.present?,
            turn_in_flight: chat_session.turn_in_flight?,
            has_more_older: has_more_older,
            messages: grouped_messages_json(messages, repository: repository),
            bookmarks: chat_session.bookmarks.includes(:chat_message).map { |bookmark| bookmark_json(bookmark) },
            attachment_groups: attachment_groups_json(attachment_groups),
            documents_in_scope: chat_session.attached_documents_in_scope.includes(:attachable).order(:title, :id).map { |document| document_json(document) },
            attachment_results: attachment_search_results(chat_session).map { |record| attachable_result_json(record) },
            whiteboard: {
              version: whiteboard&.version || 0,
              elements: whiteboard&.elements || []
            },
            paths: {
              new_chat_path: new_chat_path,
              credentials_path: edit_credentials_path,
              repositories_path: repositories_path,
              app_messages_path: "/api/v1/app/chats/#{chat_session.id}/messages",
              app_message_path: "/api/v1/app/chats/#{chat_session.id}/message",
              app_stop_path: "/api/v1/app/chats/#{chat_session.id}/stop",
              app_refresh_path: "/api/v1/app/chats/#{chat_session.id}/refresh",
              app_reset_path: "/api/v1/app/chats/#{chat_session.id}/reset",
              chat_messages_path: chat_messages_path(chat_session),
              chat_attachments_path: chat_attachments_path(chat_session),
              chat_whiteboard_path: chat_whiteboard_path(chat_session)
            }
          }
        end

        def paginated_tail(chat_session)
          scope = message_scope(chat_session)
          fetched = scope.order(created_at: :desc, id: :desc).limit(PAGE_SIZE + 1).to_a
          has_more = fetched.size > PAGE_SIZE
          [ fetched.first(PAGE_SIZE).reverse, has_more ]
        end

        def paginated_before(chat_session, before_id)
          scope = message_scope(chat_session)
          scope = scope.where("id < ?", before_id) if before_id&.positive?
          fetched = scope.order(created_at: :desc, id: :desc).limit(PAGE_SIZE + 1).to_a
          has_more = fetched.size > PAGE_SIZE
          [ fetched.first(PAGE_SIZE).reverse, has_more ]
        end

        def message_scope(chat_session)
          chat_session.messages.includes(proposal: [ :repository, :job, :epic, :target_epic, dependencies: [], child_proposals: [ :repository, dependencies: [] ] ])
        end

        def grouped_messages_json(messages, repository:)
          ChatMessageGrouper.group(messages, repository: repository).map do |item|
            if item[:type] == :tool_group
              tool_group_json(item)
            else
              message_json(item[:message], repository: repository)
            end
          end
        end

        def tool_group_json(group)
          {
            type: "tool_group",
            tool: group[:tool],
            calls: group[:calls].map do |call|
              result = call[:result]
              content = result&.content
              {
                message_id: call[:message].id,
                detail: call[:detail].to_s,
                result_body: content.is_a?(Hash) ? AgentEventAbbreviator.full_result_body(content["result"]) : content.to_s,
                result_error: content.is_a?(Hash) && content["is_error"] == true
              }
            end
          }
        end

        def message_json(message, repository:)
          text = message.content.is_a?(Hash) ? message.content["text"].to_s : message.content.to_s
          payload = {
            type: "message",
            id: message.id,
            role: message.role,
            text: text,
            bookmarkable: message.bookmarkable?,
            bookmark_path: chat_bookmarks_path(message.chat_session)
          }

          case message.role
          when "assistant"
            payload[:proposal] = proposal_json(message.proposal, repository: repository, chat_session: message.chat_session) if message.proposal_card?
          when "tool_use", "tool_result"
            payload[:tool] = structured_tool_json(message)
          when "system"
            payload[:system] = system_message_json(text)
          end

          payload
        end

        def proposal_json(proposal, repository:, chat_session:)
          return nil unless proposal

          materialized = proposal.materialized_record
          scoped_repository = proposal.effective_repository || repository
          dependencies = proposal.dependencies.order(:slug).map { |dependency| dependency.slug }
          base = {
            id: proposal.id,
            kind: proposal.kind,
            kind_label: proposal.kind.to_s.humanize,
            state: proposal.state,
            state_label: proposal.state.humanize,
            title: proposal.title,
            slug: proposal.slug,
            body: proposal.body,
            proposed: proposal.proposed?,
            resolved: proposal.resolved?,
            epic_bundle: proposal.epic_bundle?,
            scoped_repository_slug: scoped_repository&.slug,
            dependencies: dependencies,
            target_epic_label: proposal.target_epic&.display_number,
            confirm_path: chat_proposal_confirm_path(chat_session, proposal),
            reject_path: chat_proposal_reject_path(chat_session, proposal),
            materialized_label: proposal.materialized_label,
            materialized_path: materialized_path(materialized)
          }

          if proposal.epic_bundle?
            child_proposals = proposal.child_proposals.includes(:repository, :dependencies).to_a
            active_children = child_proposals.reject(&:rejected?)
            base.merge(
              active_children_count: active_children.size,
              children: child_proposals.map { |child| child_proposal_json(child, repository: repository, chat_session: chat_session) }
            )
          else
            base
          end
        end

        def child_proposal_json(proposal, repository:, chat_session:)
          {
            id: proposal.id,
            title: proposal.title,
            slug: proposal.slug,
            body: proposal.body,
            state: proposal.state,
            state_label: proposal.state.humanize,
            proposed: proposal.proposed?,
            repository_slug: proposal.repository&.slug || repository&.slug,
            dependencies: proposal.dependencies.order(:slug).map(&:slug),
            reject_path: chat_proposal_reject_path(chat_session, proposal)
          }
        end

        def structured_tool_json(message)
          content_hash = message.content.is_a?(Hash) ? message.content : {}
          tool_name = message.tool_name.presence || content_hash["name"].presence || message.role
          proposal = message.proposal
          {
            name: tool_name,
            payload: content_hash.presence || { "content" => message.content },
            proposal_id: proposal&.id,
            proposal_state_label: proposal&.state == "proposed" ? "pending" : proposal&.state
          }
        end

        def system_message_json(text)
          if (match = text.match(SYSTEM_RESULT_PATTERN))
            system_result_message(parse_system_fields(match[:payload]))
          elsif (match = text.match(SYSTEM_MCP_PATTERN))
            system_mcp_message(match[:payload])
          elsif (match = text.match(SYSTEM_CODEX_ERROR_PATTERN))
            { tone: "error", label: "Error", body: match[:message].to_s }
          else
            { tone: "neutral", label: "System", body: text }
          end
        end

        def system_result_message(fields)
          error = fields["is_error"].to_s == "true"
          subtype = fields["subtype"].to_s
          body = [ system_result_title(error, subtype) ]
          body << "#{fields['turns'].to_i} #{'turn'.pluralize(fields['turns'].to_i)}" if fields["turns"].present?
          body << system_duration_label(fields["duration_ms"]) if fields["duration_ms"].present?
          body << helpers.number_to_currency(fields["total_cost_usd"].to_f, precision: 2) if fields["total_cost_usd"].present?

          { tone: (error ? "error" : "success"), label: (error ? "Failed" : "Done"), body: body.compact.join(" · ") }
        end

        def system_result_title(error, subtype)
          return "Agent run failed#{": #{subtype.humanize}" if subtype.present?}" if error
          return "Agent run succeeded" if subtype == "success"

          subtype.present? ? "Agent run finished: #{subtype.humanize}" : "Agent run finished"
        end

        def system_mcp_message(payload)
          servers = payload.to_s.split(/\s*,\s*/).filter_map do |entry|
            name, status = entry.split("=", 2)
            next if name.blank?

            [ name, status.presence || "unknown" ]
          end
          failing = servers.reject { |_, status| status.to_s.in?(%w[connected running ready]) }
          if servers.empty?
            { tone: "neutral", label: "MCP", body: "MCP server status unavailable" }
          elsif failing.any?
            { tone: "warning", label: "MCP", body: "MCP issue: #{failing.map { |name, status| "#{name} #{status}" }.join(', ')}" }
          else
            { tone: "success", label: "Connected", body: "MCP connected: #{servers.map(&:first).join(', ')}" }
          end
        end

        def parse_system_fields(payload)
          payload.to_s.scan(/(\w+)=([^,\s]+)/).to_h
        end

        def system_duration_label(duration_ms)
          seconds = duration_ms.to_f / 1000.0
          return "#{(seconds * 10).round / 10.0}s" if seconds < 60

          minutes = seconds / 60.0
          return "#{minutes.round(1)}m" if minutes < 10

          "#{minutes.round}m"
        end

        def bookmark_json(bookmark)
          {
            id: bookmark.id,
            label: bookmark.label,
            chat_message_id: bookmark.chat_message_id
          }
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
              detach_path: chat_attachment_path(attachment.chat_session, attachment)
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

        def attachment_search_results(chat_session)
          type = normalized_search_type
          scope = attachment_search_scope(type)
          return [] unless scope

          query = params[:attachment_query].to_s.strip
          scope = filter_attachment_scope(scope, type, query) if query.present?
          attached_ids = chat_session.chat_attachments.where(attachable_type: type).select(:attachable_id)
          scope.where.not(id: attached_ids).limit(10).to_a
        end

        def normalized_search_type
          raw = params[:attachment_type].presence || params[:attachable_type].presence || "Repository"
          %w[Document RepositoryDocument].include?(raw.to_s) ? "Document" : raw.to_s
        end

        def attachment_search_scope(type)
          case type
          when "Repository"
            Current.user.repositories.active.order(:owner, :name, :id)
          when "Job"
            Current.user.jobs.includes(:repository).order(created_at: :desc, id: :desc)
          when "Document"
            Document.where(user: Current.user, attachable_type: "Repository").includes(:attachable).order(:title, :id)
          when "Epic"
            Current.user.epics.includes(:repository).order(:id)
          end
        end

        def filter_attachment_scope(scope, type, query)
          like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          case type
          when "Repository"
            scope.where("owner LIKE ? OR name LIKE ?", like, like)
          when "Job"
            id = Integer(query, exception: false)
            id ? scope.where("issue_title LIKE ? OR issue_body LIKE ? OR jobs.id = ?", like, like, id) : scope.where("issue_title LIKE ? OR issue_body LIKE ?", like, like)
          when "Document"
            scope.where("title LIKE ?", like)
          when "Epic"
            scope.where("title LIKE ?", like)
          else
            scope
          end
        end

        def attachable_result_json(record)
          {
            type: record.is_a?(Document) ? "Document" : record.class.name,
            id: record.id,
            label: attachment_label(record)
          }
        end

        def create_chat_session
          text = message_text
          repository = repository_from_params
          chat_session = nil
          user_message = nil

          ApplicationRecord.transaction do
            chat_session = ChatSession.create!(
              user: Current.user,
              repository: repository,
              title: text.presence&.truncate(80),
              last_message_at: text.present? ? Time.current : nil
            )
            if text.present?
              user_message = chat_session.messages.create!(role: "user", content: { "text" => text })
            end
          end

          ChatTurnJob.perform_later(chat_session.id, user_message.id) if user_message
          chat_session
        end

        def find_chat_session
          Current.user.chat_sessions.find(params[:id])
        end

        def message_text
          params.dig(:chat_message, :text).to_s.strip
        end

        def repository_from_params
          id = params[:repository_id].presence
          return unless id

          Current.user.repositories.find(id)
        end

        def chat_json(chat_session)
          repository = chat_session.repository
          {
            id: chat_session.id,
            title: chat_session.title,
            chat_path: chat_path(chat_session),
            repository: repository ? repository_json(repository).merge(repository_path: repository_path(repository)) : nil,
            stop_requested_at: chat_session.stop_requested_at&.iso8601,
            cumulative_input_tokens: chat_session.cumulative_input_tokens.to_i,
            cumulative_output_tokens: chat_session.cumulative_output_tokens.to_i,
            cumulative_cost_usd: chat_session.cumulative_cost.to_f
          }
        end

        def repository_json(repository)
          {
            id: repository.id,
            slug: repository.slug
          }
        end

        def attachment_label(record)
          case record
          when Repository then record.slug
          when Epic then record.display_number
          when Job then "Job ##{record.id}: #{record.issue_title.presence || record.issue_number || record.kind}"
          when Document then "#{record.title} (#{record.repository&.slug})"
          else record.try(:name).presence || record.try(:title).presence || "#{record.class.name} ##{record.id}"
          end
        end

        def materialized_path(record)
          case record
          when Job then job_path(record)
          when Epic then dashboard_epics_path
          end
        end

      end
    end
  end
end
