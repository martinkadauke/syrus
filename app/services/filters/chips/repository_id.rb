module Filters
  module Chips
    class RepositoryId < Base
      filter_name "repository_id"
      bucket :fk
      operators :is, :is_not, :is_one_of, :is_none_of

      def apply
        case op
        when :is        then scope.where(repository_id: value)
        when :is_not    then scope.where.not(repository_id: value)
        when :is_one_of then scope.where(repository_id: Array(value))
        when :is_none_of then scope.where.not(repository_id: Array(value))
        else unsupported_op!
        end
      end
    end
  end
end
