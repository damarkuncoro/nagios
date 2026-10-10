require 'rails_helper'

RSpec.describe "Hosts", type: :request do
  before do
    ActionController::Base.allow_forgery_protection = false
  end

  let(:headers) { { "Host" => "localhost", "Accept" => "text/vnd.turbo-stream.html" } }

  describe "GET /" do
    it "returns http success and renders dashboard" do
      get root_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Nagios Core Dashboard")
    end

    it "filters hosts by status and search keyword" do
      get root_path(status: 'UP', search: 'web'), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Host Status")
    end
  end

  describe "GET /hosts.csv" do
    it "returns csv content type and headers" do
      get hosts_path(format: :csv), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Host Name,Status,Checks Enabled")
    end
  end

  describe "GET /hosts/:id" do
    it "returns http success and renders host detail inspector" do
      get host_path("localhost"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("localhost")
      expect(response.body).to include("Layanan Monitored")
    end
  end

  describe "POST /hosts/:id/recheck" do
    it "schedules forced recheck" do
      post recheck_host_path("localhost"), headers: headers
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /hosts/:id/recheck_service" do
    it "schedules forced service recheck" do
      post recheck_service_host_path("localhost", service_desc: "HTTP"), headers: headers
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /hosts/:id/recheck_all_services" do
    it "schedules bulk recheck for all services and redirects back" do
      post recheck_all_services_host_path("localhost"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /hosts/:id/acknowledge_service" do
    it "acknowledges problem service" do
      post acknowledge_service_host_path("localhost", service_desc: "HTTP"), headers: headers
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /hosts/:id/schedule_service_downtime" do
    it "schedules 1-hour service downtime and redirects to downtimes path" do
      post schedule_service_downtime_host_path("localhost", service_desc: "HTTP", duration_hours: 1), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /hosts/:id/toggle_notifications" do
    it "toggles host notifications via turbo stream" do
      post toggle_notifications_host_path("localhost", enable: 'false'), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/toggle_checks" do
    it "toggles host active checks via turbo stream" do
      post toggle_checks_host_path("localhost", enable: 'true'), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/toggle_service_notifications" do
    it "toggles service notifications via turbo stream" do
      post toggle_service_notifications_host_path("localhost", service_desc: "HTTP", enable: 'false'), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/toggle_service_checks" do
    it "toggles service checks via turbo stream" do
      post toggle_service_checks_host_path("localhost", service_desc: "HTTP", enable: 'false'), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/toggle_flap_detection" do
    it "toggles host flap detection via turbo stream" do
      post toggle_flap_detection_host_path("localhost", enable: 'false'), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/toggle_service_flap_detection" do
    it "toggles service flap detection via turbo stream" do
      post toggle_service_flap_detection_host_path("localhost", service_desc: "HTTP", enable: 'false'), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/acknowledge" do
    it "acknowledges host problem via turbo stream" do
      post acknowledge_host_path("localhost"), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/remove_acknowledgment" do
    it "removes host acknowledgment (disack) via turbo stream" do
      post remove_acknowledgment_host_path("localhost"), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/remove_service_acknowledgment" do
    it "removes service acknowledgment (disack) via turbo stream" do
      post remove_service_acknowledgment_host_path("localhost", service_desc: "HTTP"), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-stream")
    end
  end

  describe "POST /hosts/:id/schedule_downtime" do
    it "schedules host downtime and redirects to downtimes path" do
      post schedule_downtime_host_path("localhost", duration_hours: 2), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /hosts/:id/schedule_cluster_downtime" do
    it "schedules cascade host and services downtime and redirects to downtimes path" do
      post schedule_cluster_downtime_host_path("localhost", duration_hours: 2), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /hosts/:id/submit_passive_check" do
    it "submits passive check and redirects back" do
      post submit_passive_check_host_path("localhost", service_desc: "HTTP", status_code: 0, output: "OK - All good"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end
end
