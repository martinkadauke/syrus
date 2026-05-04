class PollAllRepositoriesJob < ApplicationJob
  queue_as :default

  def perform
    return if AppSetting.polling_paused?
    Repository.active.where(polling_enabled: true).find_each do |repository|
      PollRepositoryJob.perform_later(repository.id)
    end
  end
end
