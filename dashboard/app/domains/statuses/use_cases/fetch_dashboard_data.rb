# frozen_string_literal: true

module Statuses
  module UseCases
    class FetchDashboardData
      def self.call(search: nil, status: nil, sort_by: nil, sort_order: :asc)
        raw_hosts = begin
          host_objs = Engines::NagiosEngine.host_objects rescue {}
          hosts_list = Engines::NagiosEngine.hosts.map do |h|
            h_hash = h.to_h
            cfg = host_objs[h_hash[:name]] || host_objs[h_hash[:name].to_s] || {}
            h_hash[:address] = cfg['address'] || cfg[:address] || h_hash[:address] || '127.0.0.1'
            h_hash[:alias] = cfg['alias'] || cfg[:alias] || h_hash[:alias] || h_hash[:name]
            h_hash[:parents] = cfg['parents'] || cfg[:parents] || '-'
            h_hash
          end

          # If runtime only returned standalone default localhost, enrich with catalog routers & snapshot states
          if hosts_list.map { |h| h[:name].to_s } == ['localhost']
            cfg_path = ENV.fetch('NAGIOS_CONFIG_FILE', Rails.root.join('config/nagios_sample.cfg').to_s)
            catalog = Statuses::Services::ObjectConfigParser.parse_file(cfg_path) rescue nil
            if catalog&.hosts&.any?
              snap_path = [ENV['NAGIOS_STATUS_FILE'], '/nagios_var/status.dat', Rails.root.join('tmp/status.dat').to_s].compact.find { |f| File.exist?(f) }
              snap = Statuses::Services::StatusDataParser.parse_file(snap_path) if snap_path rescue nil

              catalog.hosts.each do |h_name, h_cfg|
                next if h_name == 'localhost'

                h_cfg_hash = h_cfg.is_a?(Hash) ? h_cfg : (h_cfg.respond_to?(:to_h) ? h_cfg.to_h : {})
                snap_h = snap&.hosts&.dig(h_name) || {}
                st = case snap_h['current_state'].to_i
                     when 0 then 'UP'
                     when 1 then 'DOWN'
                     when 2 then 'UNREACHABLE'
                     else 'UP'
                     end

                hosts_list << {
                  name: h_name,
                  alias: h_cfg_hash['alias'] || h_cfg_hash[:alias] || h_name,
                  status: st,
                  address: h_cfg_hash['address'] || h_cfg_hash[:address] || '127.0.0.1',
                  parents: h_cfg_hash['parents'] || h_cfg_hash[:parents] || '-',
                  plugin_output: snap_h['plugin_output'].presence || 'Active network node',
                  current_attempt: snap_h['current_attempt'] || 1,
                  max_attempts: snap_h['max_attempts'] || 3,
                  last_check: snap_h['last_check'],
                  notifications_enabled: snap_h['notifications_enabled'] != 0
                }
              end
            end
          end

          hosts_list
        rescue StandardError
          []
        end

        raw_services = begin
          svc_list = Engines::NagiosEngine.services.map(&:to_h)
          # Enrich services if only localhost services present
          if raw_hosts.size > 1 && svc_list.map { |s| s[:host_name] }.uniq == ['localhost']
            snap_path = [ENV['NAGIOS_STATUS_FILE'], '/nagios_var/status.dat', Rails.root.join('tmp/status.dat').to_s].compact.find { |f| File.exist?(f) }
            snap = Statuses::Services::StatusDataParser.parse_file(snap_path) if snap_path rescue nil
            if snap&.services&.any?
              snap.services.each do |h_name, s_map|
                next if h_name == 'localhost'

                s_map.each do |s_desc, s_info|
                  s_st = case s_info['current_state'].to_i
                         when 0 then 'OK'
                         when 1 then 'WARNING'
                         when 2 then 'CRITICAL'
                         else 'UNKNOWN'
                         end
                  svc_list << {
                    host_name: h_name,
                    description: s_desc,
                    status: s_st,
                    plugin_output: s_info['plugin_output'] || '',
                    current_attempt: s_info['current_attempt'] || 1,
                    max_attempts: s_info['max_attempts'] || 3,
                    last_check: s_info['last_check']
                  }
                end
              end
            end
          end
          svc_list
        rescue StandardError
          []
        end

        program_status = begin
          Engines::NagiosEngine.program_status
        rescue StandardError
          {}
        end

        host_totals = Services::StatusQueryEngine.calculate_host_totals(raw_hosts)
        service_totals = Services::StatusQueryEngine.calculate_service_totals(raw_services)

        host_stats = {
          total: host_totals.total,
          up: host_totals.up,
          down: host_totals.down,
          unreachable: host_totals.unreachable
        }

        service_stats = {
          total: service_totals.total,
          ok: service_totals.ok,
          warning: service_totals.warning,
          critical: service_totals.critical,
          pending: service_totals.pending
        }

        has_filter = !search.to_s.strip.empty? || !status.to_s.strip.empty? || !sort_by.to_s.strip.empty?

        hosts = if has_filter
          opts = {}
          opts[:keyword] = search if !search.to_s.strip.empty?
          opts[:state] = status.to_s.upcase if !status.to_s.strip.empty?
          opts[:sort_by] = sort_by if !sort_by.to_s.strip.empty?
          opts[:sort_order] = sort_order
          Services::StatusQueryEngine.filter_hosts(raw_hosts, opts).items
        else
          raw_hosts
        end

        {
          hosts: hosts,
          services: raw_services,
          program_status: program_status,
          host_stats: host_stats,
          service_stats: service_stats,
          host_totals: host_totals,
          service_totals: service_totals
        }
      end
    end
  end
end
