require "net/http"
require "json"

class TelegramClient
  BASE = "https://api.telegram.org"

  def initialize(token: AppSetting.telegram_bot_token)
    @token = token
  end

  # GET /bot{token}/getUpdates?offset=N&timeout=T
  # Returns array of Update objects, empty array on timeout or error.
  def get_updates(offset:, timeout: 25)
    uri = URI("#{BASE}/bot#{@token}/getUpdates")
    uri.query = URI.encode_www_form(offset: offset, timeout: timeout)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.read_timeout = timeout + 10
      http.get(uri.request_uri)
    end
    data = JSON.parse(response.body)
    data["ok"] ? data["result"] : []
  rescue => e
    Rails.logger.error("TelegramClient#get_updates: #{e}")
    []
  end

  # POST /bot{token}/sendMessage
  def send_message(chat_id:, text:, parse_mode: nil)
    uri = URI("#{BASE}/bot#{@token}/sendMessage")
    body = { chat_id: chat_id, text: text }
    body[:parse_mode] = parse_mode if parse_mode
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = JSON.generate(body)
      http.request(request)
    end
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("TelegramClient#send_message: #{e}")
    nil
  end
end
