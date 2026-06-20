require "active_support/core_ext/object/blank"

module ActiveRecordEncryptionConfig
  ENV_KEYS = {
    primary_key: "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
    deterministic_key: "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
    key_derivation_salt: "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
  }.freeze

  # Fixed, non-secret development keys. They let a fresh clone round-trip
  # `encrypts :attr` columns without a master.key or any env setup. Never used
  # in production. Mirrors the same idea as the test environment's fixed keys.
  DEVELOPMENT_KEYS = {
    primary_key: "development_primary_key_at_least_32by",
    deterministic_key: "development_deterministic_key_min_32b",
    key_derivation_salt: "development_key_derivation_salt_32byt"
  }.freeze

  def self.apply_env_overrides!(config, env: ENV)
    values = ENV_KEYS.transform_values { |key| env[key].presence }
    return false if values.values.none?

    missing_keys = values.filter_map do |config_key, value|
      ENV_KEYS.fetch(config_key) if value.blank?
    end

    if missing_keys.any?
      raise KeyError, "Missing Active Record encryption environment variables: #{missing_keys.join(', ')}"
    end

    values.each do |config_key, value|
      config.active_record.encryption.public_send("#{config_key}=", value)
    end

    true
  end

  # Development should work straight from a fresh clone with no master.key.
  # Honor ACTIVE_RECORD_ENCRYPTION_* env vars when supplied (e.g. to read data
  # encrypted elsewhere); otherwise fall back to fixed development keys so
  # credentials save out of the box. Never call this in production.
  def self.apply_development_defaults!(config, env: ENV)
    return if apply_env_overrides!(config, env: env)

    DEVELOPMENT_KEYS.each do |config_key, value|
      config.active_record.encryption.public_send("#{config_key}=", value)
    end
  end
end
