require 'rails_helper'

RSpec.describe "Statusmap", type: :request do
  describe "GET /statusmap" do
    it "returns http success and renders network topology map" do
      get statusmap_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Network Topology Map")
    end
  end
end
