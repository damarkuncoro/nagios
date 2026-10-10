# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Archives", type: :request do
  let(:headers) { { "Host" => "localhost" } }

  describe "GET /api/v1/archives" do
    it "returns JSON archive data with default alertlist query" do
      get "/api/v1/archives", headers: headers
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")

      json = JSON.parse(response.body)
      expect(json["format_version"]).to eq(0)
      expect(json["result"]["cgi"]).to eq("archivejson.cgi")
      expect(json["result"]["type_code"]).to eq(0)
      expect(json["data"]).to have_key("alertlist")
    end

    it "handles help query" do
      get "/api/v1/archives?query=help", headers: headers
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["result"]["query"]).to eq("help")
      expect(json["data"]["valid_queries"]).to include("alertlist", "notificationlist", "availability")
    end

    it "handles notificationcount query" do
      get "/api/v1/archives?query=notificationcount", headers: headers
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["result"]["query"]).to eq("notificationcount")
      expect(json["data"]).to have_key("count")
      expect(json["data"]["count"]).to have_key("total")
    end

    it "handles availability query" do
      get "/api/v1/archives?query=availability", headers: headers
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["result"]["query"]).to eq("availability")
      expect(json["data"]).to have_key("availability")
    end

    it "returns option invalid error for unknown query" do
      get "/api/v1/archives?query=unknown_archive_query", headers: headers
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["result"]["type_code"]).to eq(3)
      expect(json["result"]["type_text"]).to eq("Option Invalid")
    end
  end
end
