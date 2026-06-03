require "fileutils"

class WorkspaceDependencyEnv
  def self.for(workspace_path)
    root = Pathname.new(workspace_path).join(".syrus", "deps")
    FileUtils.mkdir_p(root)
    {
      "BUNDLE_PATH" => root.join("bundle").to_s,
      "BUNDLE_APP_CONFIG" => root.join("bundle-config").to_s,
      "BUNDLE_USER_HOME" => root.join("bundle-home").to_s,
      "BUNDLE_USER_CACHE" => root.join("bundle-cache").to_s,
      "NPM_CONFIG_CACHE" => root.join("npm-cache").to_s,
      "YARN_CACHE_FOLDER" => root.join("yarn-cache").to_s,
      "COREPACK_HOME" => root.join("corepack").to_s
    }
  end
end
