require 'rails_helper'

RSpec.describe "Hostgroups", type: :request do
  describe "GET /hostgroups" do
    it "returns http success" do
      get hostgroups_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Hostgroups")
    end
  end
end
