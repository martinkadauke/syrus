module Filters
  module Chips
    # Base for chips that filter on a numeric column. `between`
    # expects value as a two-element array [min, max] (inclusive).
    class NumberColumn < Base
      bucket :number
      operators :equals, :not_equals,
                :greater_than, :less_than, :between,
                :is_set, :is_unset

      class << self
        def column(name = nil)
          @column = name.to_sym if name
          @column or raise NotImplementedError, "#{self.name} must declare `column :name`"
        end
      end

      def apply
        col = self.class.column
        case op
        when :equals       then scope.where(col => value)
        when :not_equals   then scope.where.not(col => value)
        when :greater_than then scope.where("#{quoted_column(col)} > ?", value)
        when :less_than    then scope.where("#{quoted_column(col)} < ?", value)
        when :between
          range = Array(value)
          scope.where(col => range.first..range.last)
        when :is_set       then scope.where.not(col => nil)
        when :is_unset     then scope.where(col => nil)
        else unsupported_op!
        end
      end

      private

      def quoted_column(col)
        "#{scope.connection.quote_table_name(scope.table_name)}.#{scope.connection.quote_column_name(col)}"
      end
    end
  end
end
