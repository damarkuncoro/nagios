require 'rails_helper'

RSpec.describe "PerfInfo", type: :request do
  describe "GET /perf_info" do
    it "returns http success and renders performance info" do
      get perf_info_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Performance Info")
    end

    it "returns Prometheus openmetrics format via text format" do
      get perf_info_path(format: :text), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/plain")
      expect(response.body).to include("# HELP nagios_host_up")
    end
  end

  describe "GET /metrics" do
    it "returns Prometheus metrics scrape endpoint" do
      get prometheus_metrics_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/plain")
      expect(response.body).to include("# HELP nagios_host_up")
    end
  end
end
