require 'rails_helper'

RSpec.describe "Downtimes", type: :request do
  before do
    ActionController::Base.allow_forgery_protection = false
  end

  describe "GET /downtimes" do
    it "returns http success" do
      get downtimes_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Scheduled Downtimes")
    end
  end

  describe "DELETE /downtimes/:id" do
    it "cancels downtime and redirects" do
      delete downtime_path(1), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end
end
