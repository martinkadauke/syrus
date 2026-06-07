module Api
  module V1
    module App
      class FiltersController < BaseController
        def suggestions
          render json: {
            suggestions: ::Filters::SuggestionSearch.call(
              user: Current.user,
              surface: params[:surface].presence || "dashboard",
              subject: params[:subject].presence || "job",
              query: params[:q],
              active_tree: ::Filters::QueryParam.decode(params[:active_q])
            )
          }
        rescue ArgumentError
          render_error("invalid_filter_suggestions", "Invalid filter suggestion request.", status: :bad_request)
        end

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
