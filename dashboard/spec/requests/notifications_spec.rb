require 'rails_helper'

RSpec.describe "Notifications", type: :request do
  describe "GET /notifications" do
    it "renders the notifications history page successfully" do
      get notifications_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Notification History")
      expect(response.body).to include("Audit Trail")
    end

    it "exports notifications as CSV successfully" do
      get notifications_path(format: :csv), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Timestamp,Host Name,Service Description")
    end

    it "filters notifications by contact and host" do
      get notifications_path(contact: "alice", host: "web01"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Notification History")
    end
  end
end
