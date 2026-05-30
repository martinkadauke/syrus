require "rails_helper"

RSpec.describe AppUserChannel, type: :channel do
  it "streams events for the connected user" do
    user = Factories.user
    stub_connection current_user: user

    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end
end
