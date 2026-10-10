# frozen_string_literal: true

require 'time'

module Statuses
  module Services
    # Adopts object configuration JSON API response serialization from cgi/objectjson.c
    # Implements official objectjson.cgi response envelope and standard queries:
    # (hostcount, hostlist, host, hostgroupcount, hostgrouplist, hostgroup,
    #  servicecount, servicelist, service, servicegroupcount, servicegrouplist,
    #  contactcount, contactlist, contactgroupcount, timeperiodlist, commandlist).
    class ObjectJsonSerializer
      FORMAT_VERSION = 0

      TYPE_CODES = {
        success: { code: 0, text: 'Success' },
        memory_error: { code: 1, text: 'Unable to Allocate Memory' },
        file_error: { code: 2, text: 'Unable to Open File for Reading' },
        option_invalid: { code: 3, text: 'Option Invalid' },
        option_missing: { code: 4, text: 'Option Missing' },
        option_value_missing: { code: 5, text: 'Option Value Missing' },
        option_value_invalid: { code: 6, text: 'Option Value Invalid' }
      }.freeze

      class << self
        def build_response(query:, data:, user: 'nagiosadmin', type: :success, message: '')
          new.build_response(query: query, data: data, user: user, type: type, message: message)
        end

        def serialize_query(query_name, params = {}, context = {})
          new.serialize_query(query_name, params, context)
        end
      end

      # Builds official objectjson.cgi response envelope
      def build_response(query:, data:, user: 'nagiosadmin', type: :success, message: '')
        now_ms = (Time.now.to_f * 1000).to_i
        type_info = TYPE_CODES[type.to_sym] || TYPE_CODES[:success]

        {
          format_version: FORMAT_VERSION,
          result: {
            query_time: now_ms,
            cgi: 'objectjson.cgi',
            user: user.to_s,
            query: query.to_s,
            query_status: 'released',
            type_code: type_info[:code],
            type_text: type_info[:text],
            message: message.to_s
          },
          data: data
        }
      end

      # Dispatches objectjson.cgi query
      def serialize_query(query_name, params = {}, context = {})
        q = query_name.to_s.downcase.strip
        user = context[:user] || 'nagiosadmin'

        hosts = Array(context[:hosts])
        services = Array(context[:services])
        hostgroups = Array(context[:hostgroups])
        servicegroups = Array(context[:servicegroups])
        contacts = Array(context[:contacts])
        contactgroups = Array(context[:contactgroups])
        timeperiods = Array(context[:timeperiods])
        commands = Array(context[:commands])

        case q
        when 'hostcount'
          build_response(query: q, data: { count: { total: hosts.size } }, user: user)
        when 'hostlist'
          data = serialize_host_list(hosts)
          build_response(query: q, data: data, user: user)
        when 'host'
          target_name = params[:host] || params[:name]
          host = hosts.find { |h| get_attr(h, :name).to_s.casecmp(target_name.to_s).zero? }
          if host
            build_response(query: q, data: { host: serialize_single_host(host) }, user: user)
          else
            build_response(query: q, data: {}, user: user, type: :option_value_invalid, message: "Host '#{target_name}' not found")
          end
        when 'hostgroupcount'
          build_response(query: q, data: { count: { total: hostgroups.size } }, user: user)
        when 'hostgrouplist'
          data = serialize_hostgroup_list(hostgroups)
          build_response(query: q, data: data, user: user)
        when 'servicecount'
          build_response(query: q, data: { count: { total: services.size } }, user: user)
        when 'servicelist'
          data = serialize_service_list(services)
          build_response(query: q, data: data, user: user)
        when 'servicegroupcount'
          build_response(query: q, data: { count: { total: servicegroups.size } }, user: user)
        when 'servicegrouplist'
          data = serialize_servicegroup_list(servicegroups)
          build_response(query: q, data: data, user: user)
        when 'contactcount'
          build_response(query: q, data: { count: { total: contacts.size } }, user: user)
        when 'contactlist'
          data = serialize_contact_list(contacts)
          build_response(query: q, data: data, user: user)
        when 'contactgroupcount'
          build_response(query: q, data: { count: { total: contactgroups.size } }, user: user)
        when 'contactgrouplist'
          data = serialize_contactgroup_list(contactgroups)
          build_response(query: q, data: data, user: user)
        when 'timeperiodcount'
          build_response(query: q, data: { count: { total: timeperiods.size } }, user: user)
        when 'timeperiodlist'
          data = serialize_timeperiod_list(timeperiods)
          build_response(query: q, data: data, user: user)
        when 'commandcount'
          build_response(query: q, data: { count: { total: commands.size } }, user: user)
        when 'commandlist'
          data = serialize_command_list(commands)
          build_response(query: q, data: data, user: user)
        else
          build_response(query: q, data: {}, user: user, type: :option_invalid, message: "Unknown query '#{query_name}'")
        end
      end

      private

      def serialize_host_list(hosts)
        list = {}
        hosts.each do |h|
          name = get_attr(h, :name).to_s
          list[name] = serialize_single_host(h)
        end
        { hostlist: list }
      end

      def serialize_single_host(h)
        {
          name: get_attr(h, :name).to_s,
          alias: (get_attr(h, :alias) || get_attr(h, :name)).to_s,
          address: (get_attr(h, :address) || '127.0.0.1').to_s,
          check_command: get_attr(h, :check_command).to_s,
          max_check_attempts: (get_attr(h, :max_attempts) || 3).to_i
        }
      end

      def serialize_hostgroup_list(groups)
        list = {}
        groups.each do |g|
          name = get_attr(g, :name).to_s
          list[name] = {
            name: name,
            alias: (get_attr(g, :alias) || name).to_s,
            members: Array(get_attr(g, :members) || get_attr(g, :hosts)).map { |m| get_attr(m, :name) || m.to_s }
          }
        end
        { hostgrouplist: list }
      end

      def serialize_service_list(services)
        list = {}
        services.each do |s|
          h_name = get_attr(s, :host_name).to_s
          s_desc = (get_attr(s, :description) || get_attr(s, :service_description)).to_s
          list[h_name] ||= {}
          list[h_name][s_desc] = {
            description: s_desc,
            host_name: h_name,
            check_command: get_attr(s, :check_command).to_s,
            max_check_attempts: (get_attr(s, :max_attempts) || 3).to_i
          }
        end
        { servicelist: list }
      end

      def serialize_servicegroup_list(groups)
        list = {}
        groups.each do |g|
          name = get_attr(g, :name).to_s
          list[name] = {
            name: name,
            alias: (get_attr(g, :alias) || name).to_s,
            members: Array(get_attr(g, :members) || get_attr(g, :services)).map { |m| get_attr(m, :description) || m.to_s }
          }
        end
        { servicegrouplist: list }
      end

      def serialize_contact_list(contacts)
        list = {}
        contacts.each do |c|
          name = get_attr(c, :name).to_s
          list[name] = {
            name: name,
            alias: (get_attr(c, :alias) || name).to_s,
            email: get_attr(c, :email).to_s
          }
        end
        { contactlist: list }
      end

      def serialize_contactgroup_list(groups)
        list = {}
        groups.each do |g|
          name = get_attr(g, :name).to_s
          list[name] = {
            name: name,
            alias: (get_attr(g, :alias) || name).to_s,
            members: Array(get_attr(g, :members)).map(&:to_s)
          }
        end
        { contactgrouplist: list }
      end

      def serialize_timeperiod_list(periods)
        list = {}
        periods.each do |p|
          name = (get_attr(p, :timeperiod_name) || get_attr(p, :name)).to_s
          list[name] = {
            name: name,
            alias: (get_attr(p, :alias) || name).to_s
          }
        end
        { timeperiodlist: list }
      end

      def serialize_command_list(commands)
        list = {}
        commands.each do |c|
          name = (get_attr(c, :command_name) || get_attr(c, :name)).to_s
          list[name] = {
            name: name,
            line: (get_attr(c, :command_line) || get_attr(c, :line)).to_s
          }
        end
        { commandlist: list }
      end

      def get_attr(target, key)
        return nil if target.nil?

        if target.is_a?(Hash)
          target[key.to_s] || target[key.to_sym]
        elsif target.respond_to?(key)
          target.send(key)
        end
      end
    end
  end
end
