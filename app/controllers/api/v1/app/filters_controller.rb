module Api
  module V1
    module App
      class FiltersController < BaseController
        def fk_options
          resolver = ::Filters::FkOptionsResolver.new(user: Current.user)
          render json: {
            options: resolver.resolve(field: params[:field], q: params[:q], ids: params[:ids])
          }
        rescue ::Filters::FkOptionsResolver::UnknownField
          render_error("unknown_field", "Unknown filter field.", status: :bad_request)
        end
      end
    end
  end
end
