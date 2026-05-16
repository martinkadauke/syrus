module Filters
  module Chips
    # Base class for chip implementations. Concrete chips declare their
    # bucket (drives the UI editor type) and their supported operator
    # set via the `bucket` and `operators` DSL, and override `#apply`.
    #
    #   class State < Base
    #     filter_name "state"
    #     bucket :enum
    #     operators :is, :is_not, :is_one_of, :is_none_of
    #
    #     def apply
    #       case op
    #       when :is then scope.where(state: value)
    #       ...
    #       end
    #     end
    #   end
    class Base
      class << self
        def filter_name(name = nil)
          @filter_name = name.to_s if name
          @filter_name
        end

        def bucket(name = nil)
          @bucket = name.to_sym if name
          @bucket
        end

        def operators(*ops)
          @operators = ops.map(&:to_sym).freeze if ops.any?
          @operators ||= [].freeze
        end
      end

      def initialize(scope:, op:, value:, user: nil)
        @scope = scope
        @op = op.to_sym
        @value = value
        @user = user
      end

      def apply
        raise NotImplementedError, "#{self.class} must implement #apply"
      end

      private

      attr_reader :scope, :op, :value, :user

      def unsupported_op!
        raise ArgumentError, "#{self.class.filter_name}: unsupported operator #{op.inspect}"
      end
    end
  end
end
