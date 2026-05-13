class SyncAgentSkillsJob < ApplicationJob
  include SkipIfPending

  queue_as :default

  def perform
    AgentSkillsSyncer.sync
  end
end
