require 'rails_helper'

RSpec.describe "Process Info", type: :request do
  before do
    ActionController::Base.allow_forgery_protection = false
  end

  describe "GET /process_info" do
    it "returns http success and renders Live Domain Event Broker info" do
      Statuses::Events::Broker.publish(:check, { host_name: "test-node", service_desc: "PING" }, source: "unit_test")
      get process_info_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Nagios Core Process Info")
      expect(response.body).to include("Live Domain Event Broker")
      expect(response.body).to include("test-node")
    end
  end

  describe "POST /process_info/toggle" do
    it "toggles feature and redirects" do
      post toggle_process_info_feature_path(feature: "notifications", enable: false), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /process_info/test_webhook" do
    it "triggers test webhook alert and redirects" do
      allow(Statuses::Services::NotificationService).to receive(:send_alert).and_return(true)
      post test_process_info_webhook_path, params: { webhook_url: "https://hooks.slack.com/test" }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end
end
