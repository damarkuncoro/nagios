require 'rails_helper'

RSpec.describe "Queue", type: :request do
  describe "GET /queue" do
    it "returns http success and renders scheduling queue" do
      get queue_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Scheduling Queue")
    end
  end
end
