module SyrusRails
  class MigrationDiffRenderer
    def self.artifact_type = "rails_migration_diff"
    def self.renderer_type = :migration_diff
  end
end
