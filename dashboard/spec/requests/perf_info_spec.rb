require 'rails_helper'

RSpec.describe "PerfInfo", type: :request do
  describe "GET /perf_info" do
    it "returns http success and renders performance info" do
      get perf_info_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Performance Info")
    end
  end
end
