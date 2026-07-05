module Api
  module V1
    module App
      class PlatformIdentitiesController < BaseController
        SUPPORTED_PLATFORMS = %w[ telegram slack ].freeze

        def index
          identities = Current.user.platform_identities.order(:platform)
          render json: {
            platform_identities: identities.map { |pi| identity_json(pi) },
            available_platforms: available_platforms_json
          }
        end

        def destroy
          identity = Current.user.platform_identities.find(params[:id])
          identity.destroy!
          render json: {
            message: I18n.t("api.platform_identities.unlinked"),
            platform_identities: Current.user.platform_identities.reload.order(:platform).map { |pi| identity_json(pi) },
            available_platforms: available_platforms_json
          }
        end

        def linking_token
          platform = params[:platform].to_s
          unless SUPPORTED_PLATFORMS.include?(platform)
            return render_error("bad_request", I18n.t("api.platform_identities.unsupported_platform"), status: :bad_request)
          end

          unless platform_configured?(platform)
            return render_error("not_configured", I18n.t("api.platform_identities.not_configured", platform: platform.titleize), status: :unprocessable_entity)
          end

          token = Rails.application.message_verifier(:platform_linking)
            .generate({ "user_id" => Current.user.id, "platform" => platform }, expires_in: 15.minutes)

          render json: {
            token: token,
            instructions: linking_instructions(platform, token)
          }
        end

        private

        def identity_json(identity)
          {
            id: identity.id,
            platform: identity.platform,
            external_handle: identity.external_handle,
            linked_at: identity.linked_at.iso8601
          }
        end

        def available_platforms_json
          SUPPORTED_PLATFORMS.map do |platform|
            {
              platform: platform,
              configured: platform_configured?(platform)
            }
          end
        end

        def platform_configured?(platform)
          case platform
          when "telegram" then AppSetting.telegram_configured?
          when "slack" then false
          else false
          end
        end

        def linking_instructions(platform, token)
          case platform
          when "telegram"
            bot_handle = AppSetting.telegram_bot_handle
            { text: "Send /start #{token} to @#{bot_handle} on Telegram", bot_handle: bot_handle }
          when "slack"
            { text: "This platform is not yet configured." }
          end
        end
      end
    end
  end
end
