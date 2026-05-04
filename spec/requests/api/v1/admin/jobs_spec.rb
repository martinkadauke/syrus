require "rails_helper"

RSpec.describe "API: /api/v1/admin/jobs/:id", type: :request do
  let(:admin) { Factories.user }
  let(:non_admin) { admin; Factories.user }  # second user → not admin
  let(:admin_token) { admin.generate_api_token! }
  let(:non_admin_token) { non_admin.generate_api_token! }

  let(:job) { Factories.job(user: admin) }

  def auth(token) = { "Authorization" => "Bearer #{token}" }
  def parse_body  = JSON.parse(response.body)

  describe "auth" do
    it "401s without an Authorization header" do
      get "/api/v1/admin/jobs/#{job.id}"
      expect(response).to have_http_status(:unauthorized)
      expect(parse_body.dig("error", "code")).to eq("unauthorized")
    end

    it "401s with a bogus token" do
      get "/api/v1/admin/jobs/#{job.id}", headers: auth("syrus_bogus")
      expect(response).to have_http_status(:unauthorized)
    end

    it "403s when the token belongs to a non-admin user" do
      get "/api/v1/admin/jobs/#{job.id}", headers: auth(non_admin_token)
      expect(response).to have_http_status(:forbidden)
      expect(parse_body.dig("error", "code")).to eq("forbidden")
    end

    it "200s with an admin token" do
      get "/api/v1/admin/jobs/#{job.id}", headers: auth(admin_token)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "payload shape" do
    before { sign_in_as(admin); admin_token }

    it "dumps job + repository + workflows + steps + runs in one shot" do
      # Initial workflow chain is prepare → implement → … . Set up
      # the implement step with a succeeded Run + ClaudeSession so
      # the assertions below match real production-shape data.
      wf = job.workflows.last
      implement = wf.steps.find_by(kind: "implement")
      run = implement.runs.create!(job: job, trigger_kind: "initial",
                                   state: "succeeded", agent_outcome: "success",
                                   agent_turns: 7, agent_diff: "diff --git ...",
                                   started_at: 1.minute.ago, finished_at: Time.current)
      implement.update!(state: "succeeded", finished_at: Time.current)
      wf.update!(state: "succeeded", finished_at: Time.current, cleaned_up_at: Time.current)
      ClaudeSession.create!(run: run, session_id: "abc-123",
                            transcript_jsonl: "{\"a\":1}\n{\"b\":2}\n")

      get "/api/v1/admin/jobs/#{job.id}", headers: auth(admin_token)
      body = parse_body

      expect(body["id"]).to eq(job.id)
      expect(body["state"]).to eq("open")
      expect(body["repository"]["slug"]).to eq(job.repository.slug)

      wf = body["workflows"].first
      expect(wf["trigger_kind"]).to eq("initial")
      expect(wf["state"]).to eq("succeeded")
      expect(wf["cleaned_up_at"]).to be_present
      expect(wf["retry_available"]).to be false  # cleaned up

      # First step in Initial workflow is now `prepare` (added in
      # the prep-step commit). Find implement explicitly to match
      # the Run we set up above.
      step = wf["steps"].find { |s| s["kind"] == "implement" }
      expect(step["state"]).to eq("succeeded")

      run_payload = step["runs"].first
      expect(run_payload["agent_outcome"]).to eq("success")
      expect(run_payload["agent_turns"]).to eq(7)
      expect(run_payload["agent_diff_present"]).to be true
      expect(run_payload["agent_diff_bytes"]).to be > 0
      expect(run_payload["claude_session"]["session_id"]).to eq("abc-123")
      expect(run_payload["claude_session"]["transcript_lines"]).to eq(2)
    end

    it "404s for an unknown job id with the structured error envelope" do
      get "/api/v1/admin/jobs/99999", headers: auth(admin_token)
      expect(response).to have_http_status(:not_found)
      expect(parse_body.dig("error", "code")).to eq("not_found")
    end
  end
end
