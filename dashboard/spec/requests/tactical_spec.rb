require 'rails_helper'

RSpec.describe "Tactical Overview", type: :request do
  describe "GET /tactical" do
    it "returns http success and renders tactical status overview" do
      get tactical_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Tactical Status Overview")
    end
  end
end
