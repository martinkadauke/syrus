class HomeController < ApplicationController
  def index
    @jobs = Current.user.jobs.includes(:repository).order(created_at: :desc).limit(20)
  end
end
