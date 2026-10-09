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
end
