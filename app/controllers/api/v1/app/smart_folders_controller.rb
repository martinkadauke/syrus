module Api
  module V1
    module App
      class SmartFoldersController < BaseController
        def index
          render json: smart_folders_payload
        end

        def update
          smart_folder = Current.user.smart_folders.find(params[:id])

          if smart_folder.update(smart_folder_params)
            render json: smart_folders_payload(subject_type: smart_folder.subject_type).merge(message: "Smart folder updated.")
          else
            render_error("validation_failed", smart_folder.errors.full_messages.to_sentence,
                         status: :unprocessable_content)
          end
        end

        def destroy
          smart_folder = Current.user.smart_folders.find(params[:id])
          subject_type = smart_folder.subject_type
          smart_folder.destroy!

          render json: smart_folders_payload(subject_type: subject_type).merge(message: "Smart folder deleted.")
        end

        private

        def smart_folders_payload(subject_type: smart_folder_subject)
          folders = SmartFolder.for_user(Current.user, subject: subject_type)

          {
            subject_type: subject_type,
            subject_label: subject_type.humanize,
            dashboard_path: dashboard_path_for(subject_type),
            smart_folders: folders.map { |folder| smart_folder_json(folder) }
          }
        end

        def smart_folder_json(folder)
          {
            id: folder.id,
            name: folder.name,
            position: folder.position,
            filter: folder.filter
          }
        end

        def smart_folder_params
          params.expect(smart_folder: [ :name, :position ])
        end

        def smart_folder_subject
          params[:subject_type].to_s.presence_in(SmartFolder::SUBJECT_TYPES) || "job"
        end

        def dashboard_path_for(subject_type)
          case subject_type
          when "admin_user"
            admin_users_path
          when "admin_queue"
            admin_queue_root_path
          when "workflow"
            dashboard_workflows_path
          when "epic"
            dashboard_epics_path
          when "spawned_process"
            admin_processes_path
          else
            dashboard_jobs_path
          end
        end
      end
    end
  end
end
