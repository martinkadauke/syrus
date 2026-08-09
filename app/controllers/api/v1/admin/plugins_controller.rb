module Api
  module V1
    module Admin
      class PluginsController < BaseController
        def index
          render json: ::Admin::PluginsPayload.new.as_json
        end

        def enable
          plugin = find_plugin_record
          plugin.update!(enabled: true)
          render json: ::Admin::PluginsPayload.new.as_json
        end

        def disable
          plugin = find_plugin_record
          manifest = Syrus::PluginRegistry.all_plugins.find { |candidate| candidate.name == plugin.name }
          ::Admin::PluginDisableGuard.ensure_disableable!(manifest) if manifest
          plugin.update!(enabled: false)
          render json: ::Admin::PluginsPayload.new.as_json
        rescue ActiveRecord::RecordInvalid => e
          render_error("plugin_not_disableable", e.record.errors.full_messages.to_sentence, status: :unprocessable_content)
        rescue ::Admin::PluginDisableGuard::Blocked => e
          render_error("plugin_in_use", e.message, status: :conflict)
        end

        private

        def find_plugin_record
          PluginRecord.find_by!(name: params[:name])
        end
      end
    end
  end
end
