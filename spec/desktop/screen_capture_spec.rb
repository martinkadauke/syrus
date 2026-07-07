require "rails_helper"

# The desktop shell must support the web app's walkthrough recorder:
# getDisplayMedia REJECTS in Electron unless a display-media handler is
# registered on the session the web-app window uses (the default session).
RSpec.describe "desktop screen capture" do
  def read(path)
    File.read(Rails.root.join("desktop", path))
  end

  it "registers a display-media handler on the default session at startup" do
    capture = read("electron/screenCapture.ts")
    expect(capture).to include("session.defaultSession.setDisplayMediaRequestHandler")
    # macOS: the native SCContentSharingPicker owns the Screen Recording
    # permission flow — no TCC preflight/relaunch dance.
    expect(capture).to include("useSystemPicker: true")
    # Windows/Linux fallback: primary screen via desktopCapturer.
    expect(capture).to match(/desktopCapturer\s*\.getSources\(\{ types: \["screen"\] \}\)/)
    # A capture failure must decline the request, not hang the promise.
    expect(capture).to include("callback({})")

    main = read("electron/main.ts")
    expect(main).to include("registerScreenCaptureHandler()")
  end
end
