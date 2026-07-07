module Api
  module V1
    module App
      # Multipart upload for walkthrough videos — deliberately NOT the chat
      # message base64 path (videos run 100-500MB; base64-in-JSON would 3x
      # the memory and blow request limits). The upload creates the
      # ChatVideoWalkthrough, kicks the Gemini analysis job, and returns the
      # row; progress then streams over AppUserChannel
      # (video_walkthrough.analyzing → .analyzed | .failed).
      class VideoWalkthroughsController < BaseController
        def create
          chat = Current.user.chat_sessions.find(params[:chat_id])

          unless Current.user.gemini_configured?
            render_error("gemini_not_configured",
                         "Add a Gemini API key under Credentials to analyze walkthrough videos.",
                         status: :unprocessable_content)
            return
          end

          file = params[:file]
          unless file.respond_to?(:tempfile)
            render_error("missing_file", "Attach a video file.", status: :unprocessable_content)
            return
          end

          walkthrough = chat.video_walkthroughs.new(
            user: Current.user,
            title: params[:title].presence,
            duration_seconds: duration_param,
            byte_size: file.size,
            content_type: file.content_type.to_s
          )
          walkthrough.file.attach(io: file.tempfile, filename: file.original_filename.presence || "walkthrough.webm",
                                  content_type: file.content_type.to_s)

          if walkthrough.save
            VideoWalkthroughAnalysisJob.perform_later(walkthrough.id, user_note: params[:note].presence)
            render json: { video_walkthrough: walkthrough_json(walkthrough) }, status: :created
          else
            render_error("validation_failed", walkthrough.errors.full_messages.to_sentence,
                         status: :unprocessable_content)
          end
        end

        # Re-run a failed analysis (quota blips, transient network). The
        # video is still in Active Storage, so this is free to offer.
        def retry
          walkthrough = ChatVideoWalkthrough.joins(:chat_session)
                                            .where(chat_sessions: { user_id: Current.user.id })
                                            .find(params[:id])
          unless walkthrough.failed?
            render_error("not_retryable", "Only failed analyses can be retried.", status: :unprocessable_content)
            return
          end

          walkthrough.update!(state: "uploaded", error_message: nil)
          VideoWalkthroughAnalysisJob.perform_later(walkthrough.id, user_note: params[:note].presence)
          render json: { video_walkthrough: walkthrough_json(walkthrough) }
        end

        private

        # The client measures duration (HTMLVideoElement / the recorder
        # clock); the server has no ffmpeg and Gemini decodes the video
        # itself, so this is a UX gate, not a security boundary. Clamp to
        # sane integers; reject over-limit uploads via model validation.
        def duration_param
          value = params[:duration_seconds].to_i
          value.positive? ? value : nil
        end

        def walkthrough_json(walkthrough)
          {
            id: walkthrough.id,
            chat_session_id: walkthrough.chat_session_id,
            state: walkthrough.state,
            title: walkthrough.display_title,
            duration_seconds: walkthrough.duration_seconds,
            byte_size: walkthrough.byte_size,
            error_message: walkthrough.error_message,
            created_at: walkthrough.created_at.iso8601
          }
        end
      end
    end
  end
end
