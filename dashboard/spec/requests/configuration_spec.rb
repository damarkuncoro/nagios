require 'rails_helper'

RSpec.describe "Configuration", type: :request do
  describe "GET /configuration" do
    it "returns http success and renders objects configuration" do
      get configuration_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Objects Configuration Viewer")
    end
  end
end
