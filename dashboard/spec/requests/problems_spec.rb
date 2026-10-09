require 'rails_helper'

RSpec.describe "Unhandled Problems", type: :request do
  describe "GET /problems" do
    it "returns http success and renders problems page" do
      get problems_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Unhandled Problems Center")
    end
  end
end
