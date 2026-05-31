require "rails_helper"

RSpec.describe "Job attachments", type: :request do
  let(:user) { Factories.user }
  let(:repo) { Factories.repository(user: user) }
  let(:job) { Factories.job(repository: repo) }

  before { sign_in_as(user) }

  def upload_file(name: "notes.txt", content_type: "text/plain", content: "notes")
    file = Tempfile.new([ "job-attachment", File.extname(name) ])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, original_filename: name)
  end

  it "uploads a file attachment from the Job attachments panel" do
    expect {
      post job_attachments_path(job), params: {
        job_attachment: { files: [ upload_file ] }
      }
    }.to change(Document, :count).by(1)

    expect(response).to redirect_to(job_path(job, tab: "attachments"))
    attachment = job.job_attachments.last
    expect(attachment).to be_uploaded_file
    expect(attachment.file.filename.to_s).to eq("notes.txt")
  end

  it "adds and removes a Google Doc link" do
    post job_attachments_path(job), params: {
      job_attachment: { google_doc_url: "https://docs.google.com/document/d/abc/edit" }
    }

    attachment = job.job_attachments.last
    expect(attachment).to be_google_doc_link

    expect {
      delete job_attachment_path(job, attachment)
    }.to change(Document, :count).by(-1)
    expect(response).to redirect_to(job_path(job, tab: "attachments"))
  end

end
