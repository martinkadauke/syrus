module SyrusRails
  class SchemaErdRenderer
    include Syrus::Plugin::ArtifactRenderer

    def self.artifact_type = "rails_schema_erd"
    def self.renderer_type = :erd_diagram
  end
end
