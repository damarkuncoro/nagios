class ConfigurationController < ApplicationController
  def index
    load_configuration_objects
    load_system_configurations
    @active_tab = params[:tab].presence || 'objects'
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
        load_system_configurations
        @active_tab = params[:tab].presence || 'objects'
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

  def load_system_configurations
    cgi_cfg_path = ENV.fetch('NAGIOS_CGI_CFG', Rails.root.join('../t/etc/cgi.cfg').to_s)
    @cgi_parser = File.exist?(cgi_cfg_path) ? Statuses::Services::CgiConfigParser.read(cgi_cfg_path) : nil
    @cgi_directives = @cgi_parser ? @cgi_parser.directives : {}

    main_cfg_path = ENV.fetch('NAGIOS_CFG', Rails.root.join('../t/etc/nagios.cfg').to_s)
    @main_directives = File.exist?(main_cfg_path) ? Statuses::Services::MainConfigParser.parse_file(main_cfg_path) : {}
  end
end

