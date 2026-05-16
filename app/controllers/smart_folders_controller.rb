class SmartFoldersController < ApplicationController
  before_action :set_smart_folder, only: %i[ update destroy ]

  def index
    @smart_folders = SmartFolder.for_user(Current.user)
  end

  def create
    # The save-as-folder form serializes the current filter tree into
    # a single `filter` JSON field. Fall back to the legacy URL form
    # when `filter` isn't present so a stray POST doesn't 500.
    tree = parsed_filter_tree
    filter_ast = ::Filters::Ast.parse(tree || Jobs::Filter.from_params(params).to_h)
    filter = ::Filters::Ast.serialize(filter_ast)

    if filter_ast.is_a?(::Filters::Ast::AndNode) && filter_ast.children.empty?
      redirect_to dashboard_jobs_path, alert: "Choose at least one filter before saving a smart folder."
      return
    end

    folder = Current.user.smart_folders.new(
      name: smart_folder_params[:name],
      kind: "user_defined",
      filter: filter,
      position: next_position
    )

    if folder.save
      redirect_to dashboard_jobs_path(smart_folder_id: folder.id), notice: "Smart folder saved."
    else
      redirect_to dashboard_jobs_path, alert: folder.errors.full_messages.to_sentence
    end
  rescue ArgumentError => e
    redirect_to dashboard_jobs_path, alert: "Couldn't save filter: #{e.message}"
  end

  def update
    if @smart_folder.update(smart_folder_params)
      redirect_to smart_folders_path, notice: "Smart folder updated."
    else
      redirect_to smart_folders_path, alert: @smart_folder.errors.full_messages.to_sentence
    end
  end

  def destroy
    @smart_folder.destroy!
    redirect_to smart_folders_path, notice: "Smart folder deleted."
  end

  private

  def set_smart_folder
    @smart_folder = Current.user.smart_folders.find(params[:id])
  end

  def smart_folder_params
    params.require(:smart_folder).permit(:name, :position)
  end

  def parsed_filter_tree
    raw = params[:filter]
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def next_position
    (Current.user.smart_folders.maximum(:position) || -1) + 1
  end
end
