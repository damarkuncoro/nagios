require 'rails_helper'

RSpec.describe "Trends", type: :request do
  describe "GET /trends" do
    it "returns http success and renders trends page" do
      get trends_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Trends & Historical Health")
    end
  end
end
