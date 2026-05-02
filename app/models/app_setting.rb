class AppSetting < ApplicationRecord
  # Singleton row. .current returns the only record, creating it if missing.
  def self.current
    first || create!
  end

  def self.signups_open?
    current.signups_open
  end
end
