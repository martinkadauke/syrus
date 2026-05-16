module Filters
  module Chips
    class Validity < EnumColumn
      filter_name "validity"
      label "Validity"
      column :validity
      values "valid", "duplicate", "already_implemented"
    end
  end
end
