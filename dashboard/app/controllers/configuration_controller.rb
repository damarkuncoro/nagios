class ConfigurationController < ApplicationController
  def index
    @commands = Engines::NagiosEngine.commands
    @contacts = Engines::NagiosEngine.contacts
    @timeperiods = Engines::NagiosEngine.timeperiods
    @hostgroups = Engines::NagiosEngine.hostgroups
  end
end
