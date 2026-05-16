module Filters
  module Chips
    class State < Base
      filter_name "state"
      bucket :enum
      operators :is, :is_not, :is_one_of, :is_none_of

      def apply
        case op
        when :is        then scope.where(state: value)
        when :is_not    then scope.where.not(state: value)
        when :is_one_of then scope.where(state: Array(value))
        when :is_none_of then scope.where.not(state: Array(value))
        else unsupported_op!
        end
      end
    end
  end
end
