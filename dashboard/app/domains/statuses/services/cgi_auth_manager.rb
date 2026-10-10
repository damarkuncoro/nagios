# frozen_string_literal: true

module Statuses
  module Services
    # Adopts CGI authorization logic and contact permissions from cgi/cgiauth.c
    # Checks role-based access control, system command permissions,
    # read-only flags, and object-level contact assignments.
    class CgiAuthManager
      DEFAULT_ADMIN_USERS = %w[nagiosadmin root admin].freeze

      AuthProfile = Struct.new(
        :user_name,
        :authorized_for_all_hosts,
        :authorized_for_all_services,
        :authorized_for_system_commands,
        :authorized_for_configuration_information,
        :read_only,
        keyword_init: true
      ) do
        def admin?
          authorized_for_all_hosts && authorized_for_all_services && authorized_for_system_commands && !read_only
        end
      end

      class << self
        def build_profile(user_name, config: {})
          new(config: config).build_profile(user_name)
        end

        def authorized_for_host?(user_name, host, config: {})
          new(config: config).authorized_for_host?(user_name, host)
        end

        def authorized_for_service?(user_name, service, host: nil, config: {})
          new(config: config).authorized_for_service?(user_name, service, host: host)
        end

        def can_execute_commands?(user_name, config: {})
          new(config: config).can_execute_commands?(user_name)
        end
      end

      def initialize(config: {})
        @config = config || {}
      end

      # Builds complete permission profile for user (cgi/cgiauth.c: get_authentication_information)
      def build_profile(user_name)
        u = user_name.to_s.strip
        is_default_admin = DEFAULT_ADMIN_USERS.include?(u)

        all_hosts_list = parse_auth_list(@config['authorized_for_all_hosts'])
        all_svcs_list = parse_auth_list(@config['authorized_for_all_services'])
        sys_cmds_list = parse_auth_list(@config['authorized_for_system_commands'])
        cfg_info_list = parse_auth_list(@config['authorized_for_configuration_information'])
        ro_list = parse_auth_list(@config['authorized_for_read_only'])

        AuthProfile.new(
          user_name: u,
          authorized_for_all_hosts: is_default_admin || check_list(all_hosts_list, u),
          authorized_for_all_services: is_default_admin || check_list(all_svcs_list, u),
          authorized_for_system_commands: (is_default_admin || check_list(sys_cmds_list, u)) && !check_list(ro_list, u),
          authorized_for_configuration_information: is_default_admin || check_list(cfg_info_list, u),
          read_only: check_list(ro_list, u)
        )
      end

      # Evaluates host authorization (cgi/cgiauth.c: is_authorized_for_host)
      def authorized_for_host?(user_name, host)
        profile = build_profile(user_name)
        return true if profile.authorized_for_all_hosts

        contacts = extract_contacts(host)
        contacts.include?(user_name.to_s.strip)
      end

      # Evaluates service authorization (cgi/cgiauth.c: is_authorized_for_service)
      def authorized_for_service?(user_name, service, host: nil)
        profile = build_profile(user_name)
        return true if profile.authorized_for_all_services

        s_contacts = extract_contacts(service)
        return true if s_contacts.include?(user_name.to_s.strip)

        if host
          h_contacts = extract_contacts(host)
          return true if h_contacts.include?(user_name.to_s.strip)
        end

        false
      end

      # Checks if user can execute operational commands (recheck, ack, downtime, toggles)
      def can_execute_commands?(user_name)
        profile = build_profile(user_name)
        profile.authorized_for_system_commands && !profile.read_only
      end

      private

      def parse_auth_list(raw)
        return [] if raw.nil?

        raw.to_s.split(',').map(&:strip)
      end

      def check_list(list, user)
        return false if list.empty?
        return true if list.include?('*')

        list.include?(user)
      end

      def extract_contacts(target)
        return [] if target.nil?

        contacts = []
        if target.is_a?(Hash)
          raw = target['contacts'] || target[:contacts]
          contacts = raw.is_a?(Array) ? raw : raw.to_s.split(',')
        elsif target.respond_to?(:contacts)
          raw = target.contacts
          contacts = raw.is_a?(Array) ? raw : raw.to_s.split(',')
        end

        contacts.map(&:to_s).map(&:strip).reject(&:empty?)
      end
    end
  end
end
