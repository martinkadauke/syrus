module App
  class ChatMessagePayload
    include Rails.application.routes.url_helpers
    include ActionView::Helpers::NumberHelper

    SYSTEM_RESULT_PATTERN = /\A\[(?:codex )?result\]\s+(?<payload>.+)\z/
    SYSTEM_MCP_PATTERN = /\A\[mcp_servers\]\s+(?<payload>.+)\z/
    SYSTEM_CODEX_ERROR_PATTERN = /\A\[codex error\]\s+(?<message>.+)\z/

    def self.grouped(messages, repository:)
      new(repository: repository).grouped(messages)
    end

    def initialize(repository:)
      @repository = repository
    end

    def grouped(messages)
      ChatMessageGrouper.group(messages, repository: @repository).map do |item|
        if item[:type] == :tool_group
          tool_group_json(item)
        else
          message_json(item[:message])
        end
      end
    end

    private

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

    def message_json(message)
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
        payload[:proposal] = proposal_json(message.proposal, chat_session: message.chat_session) if message.proposal_card?
      when "tool_use", "tool_result"
        payload[:tool] = structured_tool_json(message)
      when "system"
        payload[:system] = system_message_json(text)
      end

      payload
    end

    def proposal_json(proposal, chat_session:)
      return nil unless proposal

      materialized = proposal.materialized_record
      scoped_repository = proposal.effective_repository || @repository
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
        app_confirm_path: "/api/v1/app/chats/#{chat_session.id}/proposals/#{proposal.id}/confirm",
        app_reject_path: "/api/v1/app/chats/#{chat_session.id}/proposals/#{proposal.id}/reject",
        materialized_label: proposal.materialized_label,
        materialized_path: materialized_path(materialized)
      }

      if proposal.epic_bundle?
        child_proposals = proposal.child_proposals.includes(:repository, :dependencies).to_a
        active_children = child_proposals.reject(&:rejected?)
        base.merge(
          active_children_count: active_children.size,
          children: child_proposals.map { |child| child_proposal_json(child, chat_session: chat_session) }
        )
      else
        base
      end
    end

    def child_proposal_json(proposal, chat_session:)
      {
        id: proposal.id,
        title: proposal.title,
        slug: proposal.slug,
        body: proposal.body,
        state: proposal.state,
        state_label: proposal.state.humanize,
        proposed: proposal.proposed?,
        repository_slug: proposal.repository&.slug || @repository&.slug,
        dependencies: proposal.dependencies.order(:slug).map(&:slug),
        reject_path: chat_proposal_reject_path(chat_session, proposal),
        app_reject_path: "/api/v1/app/chats/#{chat_session.id}/proposals/#{proposal.id}/reject"
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
      body << number_to_currency(fields["total_cost_usd"].to_f, precision: 2) if fields["total_cost_usd"].present?

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

    def materialized_path(record)
      case record
      when Job then job_path(record)
      when Epic then dashboard_epics_path
      end
    end
  end
end
