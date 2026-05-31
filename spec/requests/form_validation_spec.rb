require "rails_helper"

RSpec.describe "Form validation feedback", type: :request do
  it "mounts global form state controllers on the non-SPA application layout" do
    get new_session_path

    expect(response).to be_successful
    expect(response.body).to include('data-controller="form-validation checkbox-persistence details-persistence"')
  end
end
