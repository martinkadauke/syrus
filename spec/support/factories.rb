module Factories
  module_function

  def user(**attrs)
    User.create!({ email_address: "user-#{SecureRandom.hex(4)}@example.com", password: "supersecret" }.merge(attrs))
  end

  def repository(**attrs)
    Repository.create!({
      user: attrs[:user] || user,
      owner: "acme",
      name: "widgets-#{SecureRandom.hex(2)}"
    }.merge(attrs))
  end

  def job(**attrs)
    repo = attrs[:repository] || repository
    Job.create!({
      user: repo.user,
      repository: repo,
      issue_number: 42
    }.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include Factories
end
