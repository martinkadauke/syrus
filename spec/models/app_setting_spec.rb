require "rails_helper"

RSpec.describe AppSetting do
  it ".current creates the singleton row on first call" do
    expect { AppSetting.current }.to change(AppSetting, :count).from(0).to(1)
  end

  it ".current returns the existing row on subsequent calls" do
    AppSetting.create!
    expect { AppSetting.current }.not_to change(AppSetting, :count)
  end

  it ".signups_open? defaults to false" do
    expect(AppSetting.signups_open?).to be false
  end

  it ".signups_open? reflects the toggle" do
    AppSetting.current.update!(signups_open: true)
    expect(AppSetting.signups_open?).to be true
  end
end
