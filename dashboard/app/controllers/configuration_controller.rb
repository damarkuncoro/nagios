class ConfigurationController < ApplicationController
  def index
    load_configuration_objects
  end

  def verify
    @report = Statuses::UseCases::VerifyConfiguration.new.call
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "verification_report_panel",
          partial: "configuration/verification_report",
          locals: { report: @report }
        )
      end
      format.html do
        load_configuration_objects
        render :index
      end
    end
  end

  private

  def load_configuration_objects
    @commands = Engines::NagiosEngine.commands
    @contacts = Engines::NagiosEngine.contacts
    @contactgroups = Engines::NagiosEngine.contactgroups
    @timeperiods = Engines::NagiosEngine.timeperiods
    @hostgroups = Engines::NagiosEngine.hostgroups
    @user_macros = Statuses::Services::MacroResolver.macros
  end
end

