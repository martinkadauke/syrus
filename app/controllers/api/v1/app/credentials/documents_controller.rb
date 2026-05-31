module Api
  module V1
    module App
      class Credentials::DocumentsController < CredentialsController
        def create
          created = []
          errors = []

          uploaded_files.each do |file|
            document = Current.user.documents.build(kind: "file", user: Current.user)
            document.file.attach(file)
            if document.save
              created << document
            else
              errors.concat(document.errors.full_messages)
            end
          end

          if google_doc_url.present?
            document = Current.user.documents.build(kind: "google_doc", google_doc_url: google_doc_url, user: Current.user)
            if document.save
              created << document
            else
              errors.concat(document.errors.full_messages)
            end
          end

          if created.any? && errors.empty?
            render json: credentials_payload(Current.user.reload).merge(message: "Document added."), status: :created
          elsif created.any?
            render json: credentials_payload(Current.user.reload).merge(message: "Some documents could not be added: #{errors.to_sentence}"),
                   status: :multi_status
          else
            render_error("validation_failed", errors.presence&.to_sentence || "Choose a file or enter a Google Doc URL.",
                         status: :unprocessable_content)
          end
        end

        def destroy
          document = Current.user.documents.find(params[:id])
          document.destroy!

          render json: credentials_payload(Current.user.reload).merge(message: "Document removed.")
        end

        private

        def uploaded_files
          Array(params.dig(:document, :files)).compact_blank
        end

        def google_doc_url
          params.dig(:document, :google_doc_url).to_s.strip
        end
      end
    end
  end
end
