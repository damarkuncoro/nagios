# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Configuration", type: :request do
  describe "GET /configuration" do
    it "returns http success and renders objects configuration explorer" do
      get configuration_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Objects Configuration Explorer")
      expect(response.body).to include("Check Commands")
      expect(response.body).to include("Pre-Flight Check")
      expect(response.body).to include("Resource Macros")
    end
  end

  describe "POST /configuration/verify" do
    it "runs pre-flight check and renders turbo stream response" do
      post verify_configuration_path,
           headers: { "Host" => "localhost", "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="verification_report_panel"')
      expect(response.body).to include("Pre-Flight Verification")
    end

    it "runs pre-flight check and renders html response" do
      post verify_configuration_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Objects Configuration Explorer")
      expect(response.body).to include("Pre-Flight Verification")
    end
  end
end
