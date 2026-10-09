require 'rails_helper'

RSpec.describe "Availability SLA Reports", type: :request do
  let(:headers) { { "Host" => "localhost" } }

  describe "GET /availability" do
    it "returns http success and renders SLA report" do
      get availability_path, headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Availability & SLA Reports")
    end

    it "exports CSV SLA report when requested with .csv format" do
      get availability_path(format: :csv), headers: headers
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Type,Host Name,Service Description,Status,Availability %,SLA Compliance")
    end
  end
end
