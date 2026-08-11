# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Feature.find_or_create_by!(slug: "terminal") do |feature|
  feature.category = "labs"
  feature.name = "Terminal"
  feature.enabled = false
end

# Development/preview sample data. Keep this intentionally small: enough to make
# a fresh preview useful for navigation, dashboard states, and chat rendering,
# but not a comprehensive fixture factory. Future agents may add one or two
# targeted rows when a UI surface is otherwise impossible to exercise, but avoid
# broad scenario dumps that slow previews or obscure real empty-state behavior.
if Rails.env.development?
  demo_user = User.find_or_initialize_by(email_address: "demo@syrus.local")
  demo_user.assign_attributes(
    name: "Demo Operator",
    first_name: "Demo",
    last_name: "Operator",
    admin: true,
    agent_provider: "codex",
    chat_provider: "codex"
  )
  demo_user.password = "password" if demo_user.new_record? || demo_user.password_digest.blank?
  demo_user.save!

  demo_repo = Repository.find_or_initialize_by(owner: "demo", name: "syrus-preview")
  demo_repo.assign_attributes(
    user: demo_user,
    default_branch: "main",
    trigger_label: "syrus",
    polling_enabled: false,
    prepare_enabled: true,
    agent_provider: "codex",
    review_policy: "self",
    feedback_policy: "confirm",
    epic_dependency_policy: "linear"
  )
  demo_repo.save!

  demo_chat = ChatSession.find_or_initialize_by(user: demo_user, title: "Preview walkthrough")
  demo_chat.assign_attributes(
    mode: "planning",
    pinned: true,
    last_message_at: Time.current
  )
  demo_chat.repository = demo_repo if demo_chat.new_record?
  demo_chat.save!

  if demo_chat.messages.none?
    ChatMessage.create!(
      chat_session: demo_chat,
      role: "user",
      content: { "text" => "Show me what is happening in this preview." }
    )
    ChatMessage.create!(
      chat_session: demo_chat,
      role: "assistant",
      content: { "text" => "This preview is seeded with a small demo repository, one epic, and representative jobs so the dashboard is not empty." }
    )
  end

  demo_epic = Epic.find_or_initialize_by(repository: demo_repo, title: "Preview the operator workflow")
  demo_epic.assign_attributes(
    user: demo_user,
    owner_user: demo_user,
    description: "Small development seed that exercises the dashboard without starting automation.",
    state: "in_progress",
    epic_dependency_policy: "linear"
  )
  demo_epic.save!

  [
    {
      title: "Inspect preview dashboard states",
      state: "implemented",
      body: "Representative implemented job with a PR waiting for review.",
      pr_number: 101,
      branch_name: "syrus/demo-dashboard-states"
    },
    {
      title: "Repair seeded background workflow",
      state: "failed",
      body: "Representative failed job for retry and failure UI affordances.",
      pr_number: 102,
      branch_name: "syrus/demo-repair-workflow"
    },
    {
      title: "Document preview seed guidance",
      state: "closed",
      body: "Representative completed job for closed-state rendering.",
      pr_number: 103,
      branch_name: "syrus/demo-seed-guidance",
      closure_reason: "pr_merged",
      finished_at: 1.hour.ago
    }
  ].each do |attrs|
    job = Job.find_or_initialize_by(
      repository: demo_repo,
      kind: "direct",
      issue_title: attrs.fetch(:title)
    )
    job.assign_attributes(
      user: demo_user,
      owner_user: demo_user,
      epic: demo_epic,
      issue_body: attrs.fetch(:body),
      state: attrs.fetch(:state),
      pr_number: attrs[:pr_number],
      branch_name: attrs[:branch_name],
      agent_provider: "codex",
      credential_mode: "pat",
      priority: "medium",
      job_provider_setting: "default",
      stack_base: "auto",
      validity: "valid",
      triaging_reason: "classifier_pending",
      closure_reason: attrs[:closure_reason],
      finished_at: attrs[:finished_at]
    )
    job.save!
  end
end
