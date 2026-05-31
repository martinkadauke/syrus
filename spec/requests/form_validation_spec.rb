require "rails_helper"

RSpec.describe "Form validation feedback", type: :request do
  let(:user) { Factories.user }

  before { sign_in_as(user) }

  it "mounts global form state controllers on the body" do
    get legacy_dashboard_jobs_path

    expect(response).to be_successful
    expect(response.body).to include('data-controller="form-validation checkbox-persistence details-persistence"')
  end
end
