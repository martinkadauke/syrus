# frozen_string_literal: true

require "spec_helper"

# The product accent is the terracotta of the winged-stylus brand mark.
# Both surfaces express it the same way: the web app remaps Tailwind's blue
# scale onto the terracotta values in config/tailwind.config.js, and the
# desktop app mirrors the identical values in the @theme block of
# desktop/src/styles.css. This spec keeps the two in sync and stops raw
# default-Tailwind blues from creeping back into the desktop CSS.
RSpec.describe "brand palette" do
  let(:repo_root) { File.expand_path("../..", __dir__) }

  def read(relative_path)
    File.read(File.join(repo_root, relative_path), encoding: "UTF-8")
  end

  let(:web_tailwind) { read("config/tailwind.config.js") }
  let(:desktop_css) { read("desktop/src/styles.css") }

  BRAND_SCALE = {
    "50" => "#faf3ef",
    "100" => "#f4e2d9",
    "200" => "#e8c3b3",
    "300" => "#dba28b",
    "400" => "#cd7a5c",
    "500" => "#c05c3f",
    "600" => "#b6492e",
    "700" => "#973b25",
    "800" => "#7a2f1e",
    "900" => "#632718",
    "950" => "#361208"
  }.freeze

  it "defines the terracotta scale and remaps blue onto it in the web app" do
    BRAND_SCALE.each do |step, hex|
      expect(web_tailwind).to include(%(#{step}: "#{hex}")), "web scale missing #{step} => #{hex}"
    end
    expect(web_tailwind).to match(/terracotta,\s*blue: terracotta/)
  end

  it "mirrors the identical scale in the desktop @theme block" do
    BRAND_SCALE.each do |step, hex|
      expect(desktop_css).to include("--color-terracotta-#{step}: #{hex};")
      expect(desktop_css).to include("--color-blue-#{step}: #{hex};")
    end
  end

  it "keeps raw default-Tailwind blues out of the desktop CSS" do
    default_blues = %w[#2563eb #1d4ed8 #3b82f6 #60a5fa #93c5fd #bfdbfe #dbeafe #eff6ff #1e40af #1e3a8a]
    default_blues.each do |hex|
      expect(desktop_css.downcase).not_to include(hex), "found default blue #{hex} in desktop/src/styles.css"
    end
  end

  it "anchors the 600 step to the brand mark's terracotta" do
    expect(BRAND_SCALE.fetch("600")).to eq("#b6492e")
  end
end
