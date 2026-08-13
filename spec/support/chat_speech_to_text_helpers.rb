module ChatSpeechToTextHelpers
  def stub_no_chat_speech_to_text_backend!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SYRUS_STT_PROVIDER").and_return(nil)
    allow(ENV).to receive(:[]).with("SYRUS_STT_WHISPER_CPP_EXECUTABLE").and_return(nil)
    allow(ENV).to receive(:[]).with("SYRUS_STT_WHISPER_CPP_MODEL").and_return(nil)
    allow(ENV).to receive(:[]).with("SYRUS_STT_BACKEND_STREAMING").and_return(nil)

    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(ChatSpeechToText::Providers::WhisperCpp::BUNDLED_EXECUTABLE_PATH).and_return(false)
    allow(File).to receive(:exist?).with(ChatSpeechToText::Providers::WhisperCpp::BUNDLED_MODEL_PATH).and_return(false)
  end
end

RSpec.configure do |config|
  config.include ChatSpeechToTextHelpers
end
