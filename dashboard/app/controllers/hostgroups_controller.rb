class HostgroupsController < ApplicationController
  def index
    @hostgroups = Engines::NagiosEngine.hostgroups
  end
end
