# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Configuration", type: :request do
  before do
    ActionController::Base.allow_forgery_protection = false
  end
  describe "GET /configuration" do
    it "returns http success and renders objects configuration explorer" do
      get configuration_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Configuration Explorer")
      expect(response.body).to include("Objects Explorer")
      expect(response.body).to include("Check Commands")
      expect(response.body).to include("Pre-Flight Check")
      expect(response.body).to include("Resource Macros")
    end

    it "renders daemon directives when tab=daemon" do
      get configuration_path(tab: "daemon"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Daemon Directives")
      expect(response.body).to include("nagios.cfg")
    end

    it "renders CGI directives when tab=cgi" do
      get configuration_path(tab: "cgi"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Web & CGI Access")
      expect(response.body).to include("cgi.cfg")
      expect(response.body).to include("Contact Authorization Matrix")
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
      expect(response.body).to include("Configuration Explorer")
      expect(response.body).to include("Pre-Flight Verification")
    end
  end
end
