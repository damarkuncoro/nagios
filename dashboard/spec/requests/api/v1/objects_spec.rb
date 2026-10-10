# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Objects", type: :request do
  let(:headers) { { "Host" => "localhost" } }

  describe "GET /api/v1/objects" do
    it "returns JSON object configuration with default hostlist query" do
      get "/api/v1/objects", headers: headers
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")

      json = JSON.parse(response.body)
      expect(json["format_version"]).to eq(0)
      expect(json["result"]["cgi"]).to eq("objectjson.cgi")
      expect(json["result"]["type_code"]).to eq(0)
      expect(json["data"]).to have_key("hostlist")
    end

    it "handles commandlist query" do
      get "/api/v1/objects?query=commandlist", headers: headers
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["result"]["query"]).to eq("commandlist")
      expect(json["data"]).to have_key("commandlist")
    end

    it "handles timeperiodlist query" do
      get "/api/v1/objects?query=timeperiodlist", headers: headers
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["result"]["query"]).to eq("timeperiodlist")
      expect(json["data"]).to have_key("timeperiodlist")
    end

    it "returns option invalid error for unknown query" do
      get "/api/v1/objects?query=unknown_object_query", headers: headers
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json["result"]["type_code"]).to eq(3)
      expect(json["result"]["type_text"]).to eq("Option Invalid")
    end
  end
end
