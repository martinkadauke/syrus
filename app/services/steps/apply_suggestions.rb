module Steps
  class ApplySuggestions < Base
    def call
      log("apply_suggestions: no suggestions to apply", kind: "system")
    end
  end
end
