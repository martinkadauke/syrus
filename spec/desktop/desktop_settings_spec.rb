# frozen_string_literal: true

require "spec_helper"

# The desktop app's persistent config moved out of main.ts so the onboarding,
# installer, and web-container modules can share it without import cycles.
# These assertions pin the module boundaries and the zero-prompt migration
# for users who configured the tray app before backend modes existed.
RSpec.describe "desktop settings and credentials modules" do
  let(:desktop_root) { File.expand_path("../../desktop", __dir__) }
  let(:main_process) { File.read(File.join(desktop_root, "electron/main.ts"), encoding: "UTF-8") }
  let(:settings_module) { File.read(File.join(desktop_root, "electron/settings.ts"), encoding: "UTF-8") }
  let(:credentials_module) { File.read(File.join(desktop_root, "electron/credentialsStore.ts"), encoding: "UTF-8") }

  it "owns the electron-store schema in settings.ts, not main.ts" do
    expect(settings_module).to include("new Store<DesktopStore>")
    expect(main_process).not_to include("new Store<")
    expect(main_process).to include('from "./settings.js"')
  end

  it "adds the backend-mode keys with onboarding-pending defaults" do
    %w[backendMode serverUrl localInstall webAppWindowBounds onboardingCompletedAt].each do |key|
      expect(settings_module).to include("#{key}:")
    end
    expect(settings_module).to include('backendMode: ""')
    expect(settings_module).to include("localInstall: null")
  end

  it "keeps the local install state under ~/.syrus/local" do
    expect(settings_module).to include('path.join(os.homedir(), ".syrus", "local")')
  end

  it "migrates existing users without prompting: credentials mean remote, a local .env means local" do
    expect(settings_module).to include("export const migrateBackendConfig")
    # Remote adoption (existing tray credentials) is checked before local.
    expect(settings_module.index("credentialsUrl")).to be < settings_module.index('".env"')
    expect(settings_module).to match(/SYRUS_PORT=/)
  end

  it "runs the migration on startup after credentials load" do
    expect(main_process).to include("await migrateBackendConfig(cachedCredentials?.url ?? null)")
    expect(main_process.index("await loadCredentials()")).to be < main_process.index("await migrateBackendConfig")
  end

  it "owns the credentials file format in credentialsStore.ts, not main.ts" do
    expect(credentials_module).to include('path.join(os.homedir(), ".syrus", "credentials")')
    expect(credentials_module).to include("mode: 0o600")
    expect(main_process).to include('from "./credentialsStore.js"')
    expect(main_process).not_to include("const parseCredentials")
    expect(main_process).not_to include('".syrus", "credentials"')
  end

  it "tolerates a missing credentials file on read and delete" do
    expect(credentials_module.scan(/ENOENT/).length).to eq(2)
  end
end
