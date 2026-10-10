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

  describe "POST /process_info/toggle_daemon" do
    it "starts and pauses daemon coordinator and redirects" do
      post toggle_daemon_path(daemon_action: "start"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to include("DIMULAI")

      post toggle_daemon_path(daemon_action: "pause"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to include("DIJEDA")
    end
  end

  describe "POST /process_info/test_tcp_probe" do
    it "executes TCP connect probe and redirects" do
      allow(Statuses::Services::NetUtils).to receive(:tcp_connect).and_return(
        Statuses::Services::NetUtils::ProbeResult.new(success: true, host: "127.0.0.1", port: 80, latency_ms: 1.5)
      )
      post test_tcp_probe_path, params: { host: "127.0.0.1", port: 80 }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to include("BERHASIL")
    end
  end

  describe "POST /process_info/execute_command" do
    it "processes external command and redirects with notice" do
      cmd = "PROCESS_SERVICE_CHECK_RESULT;web01;HTTP;0;OK - HTTP 200 OK|time=0.012s"
      post execute_command_path, params: { command_string: cmd }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to include("berhasil dieksekusi")
    end

    it "handles empty command input with alert" do
      post execute_command_path, params: { command_string: "" }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("tidak boleh kosong")
    end
  end
end
