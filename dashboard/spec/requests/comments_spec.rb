require 'rails_helper'

RSpec.describe "Comments", type: :request do
  before do
    ActionController::Base.allow_forgery_protection = false
  end

  describe "GET /comments" do
    it "returns http success" do
      get comments_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Comments Manager")
    end
  end

  describe "POST /comments" do
    it "adds service comment and redirects" do
      post comments_path, params: { host_name: "localhost", service_desc: "HTTP", comment: "Test comment" }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end

    it "adds host-only comment and redirects" do
      post comments_path, params: { host_name: "localhost", service_desc: "", comment: "Host maintenance comment" }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "DELETE /comments/:id" do
    it "deletes comment and redirects" do
      delete comment_path(1), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:redirect)
    end
  end
end
