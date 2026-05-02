require "rails_helper"

RSpec.describe "Settings", type: :request do
  let(:admin) { Factories.user }
  let(:non_admin) { Factories.user }

  it "requires authentication" do
    get edit_settings_path
    expect(response).to redirect_to(new_session_path)
  end

  context "as a non-admin" do
    before { admin; sign_in_as(non_admin) }  # force admin to be created first

    it "blocks edit" do
      get edit_settings_path
      expect(response).to redirect_to(root_path)
    end

    it "blocks update" do
      expect {
        patch settings_path, params: { app_setting: { signups_open: "1" } }
      }.not_to change { AppSetting.signups_open? }
    end
  end

  context "as an admin" do
    before { admin; sign_in_as(admin) }

    it "renders the toggle" do
      get edit_settings_path
      expect(response).to be_successful
      expect(response.body).to include("Open signups")
    end

    it "flips signups_open on" do
      patch settings_path, params: { app_setting: { signups_open: "1" } }
      expect(AppSetting.signups_open?).to be true
    end

    it "flips signups_open off" do
      AppSetting.current.update!(signups_open: true)
      patch settings_path, params: { app_setting: { signups_open: "0" } }
      expect(AppSetting.signups_open?).to be false
    end
  end
end
