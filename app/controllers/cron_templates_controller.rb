class CronTemplatesController < ApplicationController
  before_action :load_template, only: %i[ show edit update destroy ]
  helper_method :cron_templates_index_path,
                :cron_template_detail_path,
                :cron_template_edit_path,
                :cron_template_form_path,
                :new_cron_template_entry_path

  def index
    @templates = Current.user.cron_templates.order(:name)
  end

  def show
    @repositories = Current.user.repositories.active.order(:owner, :name)
    @applied_tasks = @template.scheduled_tasks.alive.includes(:repository).order(created_at: :desc)
  end

  def new
    @template = Current.user.cron_templates.build(pr_pileup_policy: "skip", enabled: true)
  end

  def create
    @template = Current.user.cron_templates.build(cron_template_params)
    if @template.save
      redirect_to cron_template_redirect_path(@template), notice: "Template created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @template.update(cron_template_params)
      redirect_to cron_template_redirect_path(@template), notice: "Template updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @template.destroy!
    redirect_to cron_templates_redirect_path, notice: "Template deleted."
  end

  private

  def load_template
    @template = Current.user.cron_templates.find(params[:id])
  end

  def cron_template_params
    params.expect(cron_template: %i[ name description prompt cron_expression pr_pileup_policy enabled ])
  end

  def cron_templates_index_path
    legacy_cron_templates_request? ? legacy_cron_templates_path : cron_templates_path
  end

  def new_cron_template_entry_path
    legacy_cron_templates_request? ? legacy_new_cron_template_path : new_cron_template_path
  end

  def cron_template_detail_path(template)
    legacy_cron_templates_request? ? legacy_cron_template_path(template) : cron_template_path(template)
  end

  def cron_template_edit_path(template)
    legacy_cron_templates_request? ? legacy_edit_cron_template_path(template) : edit_cron_template_path(template)
  end

  def cron_template_form_path(template)
    return cron_templates_index_path unless template.persisted?

    cron_template_detail_path(template)
  end

  def cron_template_redirect_path(template)
    legacy_cron_templates_request? ? legacy_cron_template_path(template) : cron_template_path(template)
  end

  def cron_templates_redirect_path
    legacy_cron_templates_request? ? legacy_cron_templates_path : cron_templates_path
  end

  def legacy_cron_templates_request?
    request.path.start_with?("/cron_templates/legacy")
  end
end
