module Filters
  module Chips
    # "Has a PR" / "No PR" — matches the existing `pr=has_pr/no_pr`
    # dropdown semantics. Will likely be augmented by a `pr_mergeable`
    # chip in a later commit; this chip is for the binary presence
    # check only.
    class PrPresent < Base
      filter_name "pr_present"
      bucket :enum
      operators :is

      def apply
        case op
        when :is
          case value.to_s
          when "has"  then scope.with_pr
          when "none" then scope.without_pr
          else scope
          end
        else unsupported_op!
        end
      end
    end
  end
end
