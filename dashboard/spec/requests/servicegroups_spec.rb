require 'rails_helper'

RSpec.describe "Servicegroups", type: :request do
  describe "GET /servicegroups" do
    it "returns http success and renders service groups page" do
      get servicegroups_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Service Groups Overview")
    end
  end
end
