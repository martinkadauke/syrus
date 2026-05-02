class RepositoriesController < ApplicationController
  before_action :load_repository, only: %i[ edit update destroy ]

  def index
    @repositories = Current.user.repositories.order(:owner, :name)
  end

  def new
    @repository = Current.user.repositories.build(default_branch: "main", trigger_label: "syrus")
  end

  def create
    @repository = Current.user.repositories.build(repository_params)
    if @repository.save
      redirect_to repositories_path, notice: "Repository #{@repository.slug} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @repository.update(repository_params)
      redirect_to repositories_path, notice: "Repository #{@repository.slug} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @repository.destroy
    redirect_to repositories_path, notice: "Repository removed."
  end

  private

  def load_repository
    @repository = Current.user.repositories.find(params[:id])
  end

  def repository_params
    params.expect(repository: [ :owner, :name, :default_branch, :trigger_label, :polling_enabled ])
  end
end
