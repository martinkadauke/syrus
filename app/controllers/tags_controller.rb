class TagsController < ApplicationController
  before_action :load_tag, only: %i[ update destroy ]
  helper_method :tags_form_path, :tag_update_path, :tag_destroy_path

  def index
    @tags = Current.user.tags.ordered.includes(:jobs)
    @tag = Current.user.tags.new(color: "gray")
  end

  def create
    @tag = Current.user.tags.new(tag_params)
    if @tag.save
      redirect_to tags_redirect_path, notice: "Tag created."
    else
      @tags = Current.user.tags.ordered.includes(:jobs)
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @tag.update(tag_params)
      redirect_to tags_redirect_path, notice: "Tag updated."
    else
      @tags = Current.user.tags.ordered.includes(:jobs)
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    @tag.destroy!
    redirect_to tags_redirect_path, notice: "Tag deleted."
  end

  private

  def load_tag
    @tag = Current.user.tags.find(params[:id])
  end

  def tag_params
    params.require(:tag).permit(:name, :color)
  end

  def tags_form_path
    legacy_tags_request? ? legacy_tags_path : tags_path
  end

  def tag_update_path(tag)
    legacy_tags_request? ? legacy_tag_path(tag) : tag_path(tag)
  end

  def tag_destroy_path(tag)
    legacy_tags_request? ? legacy_tag_path(tag) : tag_path(tag)
  end

  def tags_redirect_path
    legacy_tags_request? ? legacy_tags_path : tags_path
  end

  def legacy_tags_request?
    request.path.start_with?("/tags/legacy")
  end
end
