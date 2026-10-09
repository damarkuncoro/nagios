require 'rails_helper'

RSpec.describe "Summary", type: :request do
  describe "GET /summary" do
    it "returns http success and renders summary page" do
      get summary_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Top Incidents & Alert Totals")
    end
  end
end
