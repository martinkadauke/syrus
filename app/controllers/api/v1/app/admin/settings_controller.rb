module Api
  module V1
    module App
      module Admin
        class SettingsController < BaseController
          def show
            render json: settings_payload
          end

          def update
            setting = AppSetting.current

            if setting.update(settings_params)
              render json: settings_payload.merge(message: "Settings updated.")
            else
              render_error("validation_failed", setting.errors.full_messages.to_sentence,
                           status: :unprocessable_content)
            end
          end

          def clear_secret
            label = AppSetting::CLEARABLE_SECRETS[params[:secret].to_s]
            return render_error("unknown_secret", "Unknown secret.", status: :unprocessable_content) unless label

            AppSetting.current.clear_secret!(params[:secret])
            render json: settings_payload.merge(message: "#{label} cleared.")
          end

          private

          def settings_payload
            setting = AppSetting.current
            {
              settings: {
                signups_open: setting.signups_open,
                clearable_secrets: AppSetting::CLEARABLE_SECRETS.map do |key, label|
                  {
                    key: key,
                    label: label,
                    set: setting.public_send(key).present?
                  }
                end
              }
            }
          end

          def settings_params
            params
              .expect(app_setting: [ :signups_open, :telegram_bot_token, :telegram_webhook_secret ])
              .to_h
              .reject { |key, value| key != "signups_open" && value.blank? }
          end
        end
      end
    end
  end
end
