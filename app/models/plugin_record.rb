class PluginRecord < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validate :enabled_plugin_is_disableable

  # Installation means the gem's engine registered during this boot. Enabling and
  # disabling installed plugins takes effect for new requests because registry
  # lookups consult this row every time.

  after_initialize do
    self.config ||= {}
    self.default_enabled = true if has_attribute?(:default_enabled) && default_enabled.nil?
    self.disableable = true if has_attribute?(:disableable) && disableable.nil?
  end

  def effective_enabled?
    enabled? || !disableable?
  end

  private

  def enabled_plugin_is_disableable
    return unless has_attribute?(:disableable)
    return if enabled?
    return if disableable?

    errors.add(:enabled, "cannot be false for a non-disableable plugin")
  end
end
