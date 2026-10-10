# frozen_string_literal: true

require 'time'

module Statuses
  module Services
    # Adopts standard JSON API response serialization from cgi/statusjson.c & cgi/jsonutils.c
    # Implements the official statusjson.cgi response envelope, standard queries
    # (hostcount, hostlist, servicecount, servicelist, programstatus, downtimelist, commentlist),
    # and Nagios error code handling.
    class StatusJsonSerializer
      FORMAT_VERSION = 0

      TYPE_CODES = {
        success: { code: 0, text: 'Success' },
        memory_error: { code: 1, text: 'Unable to Allocate Memory' },
        file_error: { code: 2, text: 'Unable to Open File for Reading' },
        option_invalid: { code: 3, text: 'Option Invalid' },
        option_missing: { code: 4, text: 'Option Missing' },
        option_value_missing: { code: 5, text: 'Option Value Missing' },
        option_value_invalid: { code: 6, text: 'Option Value Invalid' },
        option_ignored: { code: 7, text: 'Option Ignored' }
      }.freeze

      class << self
        def build_response(query:, data:, user: 'nagiosadmin', program_start: nil, last_update: nil, type: :success, message: '')
          new.build_response(
            query: query,
            data: data,
            user: user,
            program_start: program_start,
            last_update: last_update,
            type: type,
            message: message
          )
        end

        def build_error(query:, type: :option_invalid, message: '', user: 'nagiosadmin')
          new.build_error(query: query, type: type, message: message, user: user)
        end

        def serialize_query(query_name, params = {}, context = {})
          new.serialize_query(query_name, params, context)
        end
      end

      # Formats response envelope (cgi/statusjson.c: print_json_header & print_json_footer)
      def build_response(query:, data:, user: 'nagiosadmin', program_start: nil, last_update: nil, type: :success, message: '')
        now_ms = (Time.now.to_f * 1000).to_i
        prog_start_ms = program_start ? (to_time(program_start).to_f * 1000).to_i : (now_ms - 3600_000)
        last_update_ms = last_update ? (to_time(last_update).to_f * 1000).to_i : now_ms

        type_info = TYPE_CODES[type.to_sym] || TYPE_CODES[:success]

        {
          format_version: FORMAT_VERSION,
          result: {
            query_time: now_ms,
            cgi: 'statusjson.cgi',
            user: user.to_s,
            query: query.to_s,
            query_status: 'released',
            program_start: prog_start_ms,
            last_data_update: last_update_ms,
            type_code: type_info[:code],
            type_text: type_info[:text],
            message: message.to_s
          },
          data: data
        }
      end

      def build_error(query:, type: :option_invalid, message: '', user: 'nagiosadmin')
        build_response(
          query: query,
          data: {},
          user: user,
          type: type,
          message: message
        )
      end

      # Dispatches standard statusjson.cgi queries
      def serialize_query(query_name, params = {}, context = {})
        q = query_name.to_s.downcase.strip
        hosts = Array(context[:hosts])
        services = Array(context[:services])
        program_status = context[:program_status] || {}
        downtimes = Array(context[:downtimes])
        comments = Array(context[:comments])
        user = context[:user] || 'nagiosadmin'

        case q
        when 'hostcount'
          data = serialize_host_count(hosts)
          build_response(query: q, data: data, user: user)
        when 'hostlist'
          data = serialize_host_list(hosts, params)
          build_response(query: q, data: data, user: user)
        when 'servicecount'
          data = serialize_service_count(services)
          build_response(query: q, data: data, user: user)
        when 'servicelist'
          data = serialize_service_list(services, params)
          build_response(query: q, data: data, user: user)
        when 'programstatus'
          data = serialize_program_status(program_status)
          build_response(query: q, data: data, user: user)
        when 'downtimelist'
          data = serialize_downtimes(downtimes)
          build_response(query: q, data: data, user: user)
        when 'commentlist'
          data = serialize_comments(comments)
          build_response(query: q, data: data, user: user)
        else
          build_error(query: q, type: :option_invalid, message: "Unknown query '#{query_name}'", user: user)
        end
      end

      private

      def serialize_host_count(hosts)
        totals = StatusQueryEngine.calculate_host_totals(hosts)
        {
          count: {
            total: totals.total,
            up: totals.up,
            down: totals.down,
            unreachable: totals.unreachable,
            pending: totals.pending
          }
        }
      end

      def serialize_host_list(hosts, params)
        res = StatusQueryEngine.filter_hosts(hosts, params)
        list = {}
        res.items.each do |h|
          name = get_attr(h, :name).to_s
          list[name] = {
            name: name,
            status: get_attr(h, :status),
            plugin_output: get_attr(h, :plugin_output),
            current_attempt: get_attr(h, :current_attempt),
            max_attempts: get_attr(h, :max_attempts),
            last_check: get_attr(h, :last_check),
            next_check: get_attr(h, :next_check),
            acknowledged: is_truthy?(get_attr(h, :acknowledged))
          }
        end
        { hostlist: list }
      end

      def serialize_service_count(services)
        totals = StatusQueryEngine.calculate_service_totals(services)
        {
          count: {
            total: totals.total,
            ok: totals.ok,
            warning: totals.warning,
            critical: totals.critical,
            unknown: totals.unknown,
            pending: totals.pending
          }
        }
      end

      def serialize_service_list(services, params)
        res = StatusQueryEngine.filter_services(services, params)
        list = {}
        res.items.each do |s|
          h_name = get_attr(s, :host_name).to_s
          s_desc = (get_attr(s, :description) || get_attr(s, :service_description)).to_s
          list[h_name] ||= {}
          list[h_name][s_desc] = {
            description: s_desc,
            host_name: h_name,
            status: get_attr(s, :status),
            plugin_output: get_attr(s, :plugin_output),
            last_check: get_attr(s, :last_check),
            next_check: get_attr(s, :next_check),
            acknowledged: is_truthy?(get_attr(s, :acknowledged))
          }
        end
        { servicelist: list }
      end

      def serialize_program_status(prog)
        {
          programstatus: {
            version: get_attr(prog, :version) || '4.5.12',
            program_start: get_attr(prog, :program_start),
            is_currently_running: is_truthy?(get_attr(prog, :is_currently_running) != false),
            notifications_enabled: is_truthy?(get_attr(prog, :enable_notifications) != false),
            active_service_checks_enabled: is_truthy?(get_attr(prog, :execute_service_checks) != false),
            passive_service_checks_enabled: is_truthy?(get_attr(prog, :accept_passive_service_checks) != false)
          }
        }
      end

      def serialize_downtimes(downtimes)
        list = {}
        downtimes.each do |d|
          id = (get_attr(d, :downtime_id) || get_attr(d, :id)).to_s
          list[id] = {
            downtime_id: id,
            host_name: get_attr(d, :host_name),
            service_description: get_attr(d, :service_description),
            author: get_attr(d, :author),
            comment: get_attr(d, :comment),
            start_time: get_attr(d, :start_time),
            end_time: get_attr(d, :end_time),
            fixed: is_truthy?(get_attr(d, :fixed))
          }
        end
        { downtimelist: list }
      end

      def serialize_comments(comments)
        list = {}
        comments.each do |c|
          id = (get_attr(c, :comment_id) || get_attr(c, :id)).to_s
          list[id] = {
            comment_id: id,
            host_name: get_attr(c, :host_name),
            service_description: get_attr(c, :service_description),
            author: get_attr(c, :author),
            comment_data: get_attr(c, :comment_data) || get_attr(c, :data),
            entry_time: get_attr(c, :entry_time)
          }
        end
        { commentlist: list }
      end

      def to_time(val)
        case val
        when Time then val
        when Numeric then Time.at(val.to_i)
        when String
          begin
            Time.parse(val)
          rescue StandardError
            Time.now
          end
        else
          Time.now
        end
      end

      def is_truthy?(val)
        val == true || val == 1 || val.to_s == '1' || val.to_s.casecmp('true').zero?
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
