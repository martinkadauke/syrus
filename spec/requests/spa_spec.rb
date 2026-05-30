require "rails_helper"

RSpec.describe "SPA shell", type: :request do
  it "uses the normal HTML authentication flow when signed out" do
    Factories.user

    get app_shell_path

    expect(response).to redirect_to(new_session_path)
  end

  it "renders the React mount for signed-in users" do
    user = Factories.user
    sign_in_as(user)

    get app_shell_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="syrus-spa-root"')
    expect(response.body).to include("<title>Syrus</title>")
    expect(response.body).not_to include("javascript_importmap")
  end
end
