module Filters
  # Serializes Filters::Registry into a JSON-friendly array that
  # describes every chip type's bucket, operator vocabulary, value
  # set (when statically known), and human label. The chip-bar UI
  # consumes this to render add-filter menus and per-chip editors.
  module Schema
    module_function

    # Returns an Array<Hash> with one entry per registered chip,
    # ordered by Registry::CHIPS' declaration order so the add-filter
    # menu shows fields in the logical grouping the registry uses.
    def for_user(user)
      Registry::CHIPS.keys.map { |field| chip_for(field, user: user) }
    end

    def chip_for(field, user: nil)
      chip = Registry.find(field)
      meta = {
        "field"     => field,
        "label"     => chip.label,
        "bucket"    => chip.bucket.to_s,
        "operators" => chip.operators.map(&:to_s),
        "values"    => dynamic_values(chip, user) || chip.values
      }
      meta["expansions"] = chip.expansions if chip.respond_to?(:expansions)
      meta
    end

    # FK chips (repository_id, epic_id, parent_job_id) need
    # per-user value lists. The schema embeds them inline so the
    # chip-bar UI doesn't need an extra autocomplete round-trip
    # for the small data sets a single user owns.
    def dynamic_values(chip, user)
      return nil unless user

      case chip.filter_name
      when "repository_id"
        user.repositories.active.order(:owner, :name).map { |r| { "value" => r.id, "label" => r.slug } }
      when "epic_id"
        user.epics.includes(:repository).order(:title).map { |e| { "value" => e.id, "label" => epic_label(e) } }
      when "parent_job_id"
        user.jobs.where.not(branch_name: nil).order(created_at: :desc).limit(200).map do |job|
          { "value" => job.id, "label" => "##{job.issue_number || job.id} #{job.issue_title}".strip }
        end
      when "tags"
        user.tags.order(Arel.sql("LOWER(tags.name)")).map { |t| { "value" => t.id, "label" => t.name } }
      else
        nil
      end
    rescue NoMethodError
      # If the user model doesn't expose one of these associations
      # (test fixtures, partial migrations, etc.) — fall back to the
      # static `values` list. The chip stays usable as a free input.
      nil
    end

    def epic_label(epic)
      number = epic.respond_to?(:number) ? epic.number : epic.id
      "EPIC-#{number} #{epic.title}".strip
    end
  end
end
