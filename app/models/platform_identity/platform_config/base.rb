class PlatformIdentity::PlatformConfig::Base
  def self.for(platform)
    {
      "telegram" => PlatformIdentity::PlatformConfig::Telegram,
      "slack" => PlatformIdentity::PlatformConfig::Slack
    }.fetch(platform.to_s).new
  end

  def configured?
    raise NotImplementedError
  end

  def instructions(_token)
    raise NotImplementedError
  end
end
