class PlatformIdentity::PlatformConfig::Telegram < PlatformIdentity::PlatformConfig::Base
  def configured?
    AppSetting.telegram_configured?
  end

  def instructions(token)
    bot_handle = AppSetting.telegram_bot_handle
    {
      text: "Send /start #{token} to @#{bot_handle} on Telegram",
      bot_handle: bot_handle
    }
  end
end
