class ServicegroupsController < ApplicationController
  def index
    @servicegroups = Statuses::UseCases::FetchServicegroups.call
  end
end
