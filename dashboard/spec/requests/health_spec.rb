# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Health", type: :request do
  describe "GET /healthz" do
    it "returns health status json" do
      allow(Engines::NagiosEngine).to receive(:program_status).and_return({ version: '4.4.6', pid: 1234 })

      get "/healthz", headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:ok)
      
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("healthy")
      expect(json["checks"]["app"]).to eq("ok")
      expect(json["checks"]["nagios_engine"]).to eq("connected")
    end

    it "returns degraded status when engine is unavailable" do
      allow(Engines::NagiosEngine).to receive(:program_status).and_raise(StandardError.new("connection error"))

      get "/healthz", headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:service_unavailable)

      json = JSON.parse(response.body)
      expect(json["status"]).to eq("degraded")
      expect(json["checks"]["nagios_engine"]).to eq("unavailable")
    end
  end

  describe "GET /up" do
    it "returns ok for rails standard healthcheck" do
      allow(Engines::NagiosEngine).to receive(:program_status).and_return({ version: '4.4.6', pid: 1234 })

      get "/up", headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:ok)
    end
  end
end
