module SignInHelpers
  def sign_in_as(user, password: "supersecret")
    post session_url, params: { email_address: user.email_address, password: password }
  end
end

RSpec.configure do |config|
  config.include SignInHelpers, type: :request
end
