require "net/http"
require "json"

module Gemini
  # Minimal client for the Google AI (generativelanguage.googleapis.com) API,
  # scoped to exactly what walkthrough analysis needs: key validation, Files
  # API upload (resumable protocol — videos are 100-500MB), file-state
  # polling, and one generateContent call with a JSON responseSchema.
  #
  # Auth is an AI Studio API key ONLY. The gemini-cli OAuth path talks to the
  # Code Assist API, which has no Files API — and reusing its OAuth client in
  # third-party apps is an enforced ToS violation. Keys are free
  # (aistudio.google.com/apikey) and validate with a free models.list ping.
  class Client
    BASE_URL = "https://generativelanguage.googleapis.com".freeze
    API_VERSION = "v1beta".freeze
    # Flash tier: free-tier eligible, native video+audio, structured outputs.
    DEFAULT_MODEL = "gemini-3.5-flash".freeze
    # Videos this long or longer analyze at low media resolution (~100 vs
    # ~300 tokens/sec) so a 15-minute walkthrough stays inside free-tier
    # per-minute token windows. Screen content at Gemini's 1 fps sampling
    # survives low resolution fine.
    LOW_RESOLUTION_THRESHOLD_SECONDS = 12 * 60

    Error = Class.new(StandardError)
    # 400/401/403 — key invalid, revoked, or project-restricted.
    AuthError = Class.new(Error)
    # 429 — free-tier quota exhausted; caller should surface "try later".
    RateLimited = Class.new(Error)
    # Files API upload processed but the file landed in state FAILED.
    FileProcessingFailed = Class.new(Error)

    def initialize(api_key:, model: DEFAULT_MODEL)
      raise ArgumentError, "api_key required" if api_key.blank?

      @api_key = api_key
      @model = model
    end

    attr_reader :model

    # Cheap key validation: models.list is free and requires a working key.
    # Returns the list of model names (used to confirm a video-capable flash
    # model is actually available to this key's project).
    def list_models
      response = request(Net::HTTP::Get.new(uri_for("/#{API_VERSION}/models?pageSize=50")))
      json = parse!(response)
      Array(json["models"]).map { |m| m["name"].to_s.delete_prefix("models/") }
    end

    # Files API resumable upload. Returns { "uri" =>, "name" =>, "state" => }.
    # The file enters PROCESSING server-side; callers poll wait_until_active
    # before generateContent can reference it.
    def upload_file(io:, byte_size:, content_type:, display_name:)
      start_uri = uri_for("/upload/#{API_VERSION}/files")
      start = Net::HTTP::Post.new(start_uri)
      start["X-Goog-Upload-Protocol"] = "resumable"
      start["X-Goog-Upload-Command"] = "start"
      start["X-Goog-Upload-Header-Content-Length"] = byte_size.to_s
      start["X-Goog-Upload-Header-Content-Type"] = content_type
      start["Content-Type"] = "application/json"
      start.body = { file: { display_name: display_name } }.to_json

      start_response = request(start)
      parse!(start_response) if start_response.code.to_i >= 400
      upload_url = start_response["x-goog-upload-url"]
      raise Error, "Gemini did not return a resumable upload URL" if upload_url.blank?

      upload_uri = URI.parse(upload_url)
      upload = Net::HTTP::Post.new(upload_uri)
      upload["X-Goog-Upload-Command"] = "upload, finalize"
      upload["X-Goog-Upload-Offset"] = "0"
      upload["Content-Length"] = byte_size.to_s
      upload.body_stream = io

      json = parse!(request(upload, uri: upload_uri, read_timeout: 600))
      json.fetch("file")
    end

    def file_state(name)
      response = request(Net::HTTP::Get.new(uri_for("/#{API_VERSION}/#{name}")))
      parse!(response)
    end

    # Poll until the uploaded video finishes server-side processing. Video
    # processing scales with length; a 15-min recording typically takes tens
    # of seconds. The interval is injectable so specs don't sleep.
    def wait_until_active(name, timeout: 300, interval: 5, sleeper: ->(s) { sleep(s) })
      deadline = Time.current + timeout
      loop do
        file = file_state(name)
        state = file["state"].to_s
        return file if state == "ACTIVE"
        raise FileProcessingFailed, "Gemini could not process the video (state FAILED)" if state == "FAILED"
        raise Error, "timed out waiting for Gemini to process the video" if Time.current >= deadline

        sleeper.call(interval)
      end
    end

    # One multimodal call: video (by Files API URI) + instruction, constrained
    # to a JSON responseSchema. media_resolution drops to LOW for long videos
    # (free-tier token-window fit + 3x cheaper, negligible quality loss for
    # 1fps-sampled screen content).
    def generate_content(file_uri:, mime_type:, prompt:, response_schema:, duration_seconds: nil)
      body = {
        contents: [
          {
            role: "user",
            parts: [
              { file_data: { file_uri: file_uri, mime_type: mime_type } },
              { text: prompt }
            ]
          }
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: response_schema
        }.merge(media_resolution_config(duration_seconds))
      }

      post = Net::HTTP::Post.new(uri_for("/#{API_VERSION}/models/#{@model}:generateContent"))
      post["Content-Type"] = "application/json"
      post.body = body.to_json

      json = parse!(request(post, read_timeout: 600))
      text = json.dig("candidates", 0, "content", "parts", 0, "text").to_s
      raise Error, "Gemini returned an empty analysis" if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError
      raise Error, "Gemini returned malformed JSON despite the response schema"
    end

    private

    def media_resolution_config(duration_seconds)
      return {} if duration_seconds.nil? || duration_seconds < LOW_RESOLUTION_THRESHOLD_SECONDS

      { mediaResolution: "MEDIA_RESOLUTION_LOW" }
    end

    def uri_for(path)
      URI.parse("#{BASE_URL}#{path}")
    end

    def request(req, uri: req.uri, read_timeout: 60)
      req["x-goog-api-key"] = @api_key
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: read_timeout, open_timeout: 15) do |http|
        http.request(req)
      end
    end

    def parse!(response)
      code = response.code.to_i
      body = response.body.to_s
      json = body.present? ? (JSON.parse(body) rescue {}) : {}

      case code
      when 200..299 then json
      when 401, 403 then raise AuthError, api_message(json, "Gemini rejected this API key.")
      when 429 then raise RateLimited, api_message(json, "Gemini's quota is busy right now.")
      when 400
        message = api_message(json, "Gemini rejected the request.")
        raise message.match?(/API key/i) ? AuthError.new(message) : Error.new(message)
      else
        raise Error, api_message(json, "Gemini request failed (HTTP #{code}).")
      end
    end

    def api_message(json, fallback)
      json.dig("error", "message").presence || fallback
    end
  end
end
