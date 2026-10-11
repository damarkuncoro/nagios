class ApplicationController < ActionController::Base
  helper_method :current_user, :current_user_profile

  def current_user
    ENV.fetch('NAGIOS_AUTH_USER', 'nagiosadmin')
  end

  def current_user_profile
    @current_user_profile ||= Statuses::Services::CgiAuthManager.build_profile(current_user)
  end
end
