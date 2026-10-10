# frozen_string_literal: true

module Statuses
  module UseCases
    class VerifyConfiguration
      VerificationResult = Struct.new(:valid?, :errors, :warnings, :metrics, :summary, keyword_init: true)

      def initialize(engine: Engines::NagiosEngine)
        @engine = engine
      end

      def call
        commands = load_commands
        host_objs = load_hosts
        service_objs = load_services
        timeperiods = load_timeperiods

        errors = []
        warnings = []

        # 1. Pre-flight object check (base/config.c: pre_flight_object_check)
        check_hosts(host_objs, commands, timeperiods, errors, warnings)
        check_services(service_objs, host_objs, commands, timeperiods, errors, warnings)

        # 2. Pre-flight circular check (base/config.c: pre_flight_circular_check)
        circular_loops = check_circular_host_dependencies(host_objs, errors)

        total_services_count = count_services(service_objs)

        VerificationResult.new(
          valid?: errors.empty?,
          errors: errors,
          warnings: warnings,
          metrics: {
            hosts_checked: host_objs.size,
            services_checked: total_services_count,
            commands_checked: commands.size,
            circular_loops_detected: circular_loops
          },
          summary: errors.empty? ? "Things look okay - No serious problems were detected during the pre-flight check." : "Errors detected in configuration! Pre-flight check failed with #{errors.size} error(s)."
        )
      end

      private

      def check_hosts(hosts, commands, timeperiods, errors, warnings)
        hosts.each do |host_name, data|
          h = data.is_a?(Hash) ? data : {}
          cmd_name = extract_bang_command(h['check_command'])
          if cmd_name.present? && !commands.key?(cmd_name)
            errors << "Error: Host '#{host_name}' references undefined check_command '#{cmd_name}'"
          end

          [h['check_period'], h['notification_period']].compact.reject(&:empty?).each do |tp|
            unless timeperiods.include?(tp)
              warnings << "Warning: Host '#{host_name}' references undefined timeperiod '#{tp}'"
            end
          end
        end
      end

      def check_services(services_map, hosts, commands, timeperiods, errors, warnings)
        services_map.each do |host_name, svcs|
          unless hosts.key?(host_name)
            errors << "Error: Service collection references undefined host '#{host_name}'"
          end

          svcs_hash = svcs.is_a?(Hash) ? svcs : {}
          svcs_hash.each do |svc_desc, s_info|
            s = s_info.is_a?(Hash) ? s_info : {}
            cmd_name = extract_bang_command(s['check_command'])
            if cmd_name.present? && !commands.key?(cmd_name)
              errors << "Error: Service '#{svc_desc}' on host '#{host_name}' references undefined check_command '#{cmd_name}'"
            end

            [s['check_period'], s['notification_period']].compact.reject(&:empty?).each do |tp|
              unless timeperiods.include?(tp)
                warnings << "Warning: Service '#{svc_desc}' on host '#{host_name}' references undefined timeperiod '#{tp}'"
              end
            end
          end
        end
      end

      def check_circular_host_dependencies(hosts, errors)
        loops_found = 0
        visited = {}

        hosts.each_key do |host_name|
          next if visited[host_name] == :done

          path = []
          if has_cycle?(host_name, hosts, visited, path)
            loops_found += 1
            errors << "Error: Circular path detected between hosts: #{path.join(' -> ')}"
          end
        end
        loops_found
      end

      def has_cycle?(node, hosts, visited, path)
        return false unless hosts.key?(node)

        visited[node] = :visiting
        path << node

        parents = (hosts.dig(node, 'parent_hosts') || hosts.dig(node, 'parents') || [])
        parents.each do |parent|
          if visited[parent] == :visiting
            path << parent
            return true
          elsif visited[parent] != :done && has_cycle?(parent, hosts, visited, path)
            return true
          end
        end

        visited[node] = :done
        path.pop
        false
      end

      def extract_bang_command(cmd)
        return nil if cmd.blank?
        cmd.to_s.split('!').first.strip
      end

      def count_services(services_map)
        services_map.values.sum { |s| s.is_a?(Hash) ? s.size : 1 }
      end

      def load_commands
        cmds = @engine.commands rescue []
        cmds.each_with_object({}) do |c, h|
          name = c.is_a?(Hash) ? c['name'] : c.to_s
          h[name] = c
        end
      end

      def load_hosts
        hosts = begin
          @engine.host_objects
        rescue StandardError
          nil
        end
        return hosts if hosts.is_a?(Hash)

        begin
          (@engine.hosts || []).each_with_object({}) do |h, acc|
            name = h.respond_to?(:name) ? h.name : h['name']
            acc[name] = { 'name' => name, 'check_command' => 'check-host-alive' }
          end
        rescue StandardError
          {}
        end
      end

      def load_services
        svcs = begin
          @engine.service_objects
        rescue StandardError
          nil
        end
        return svcs if svcs.is_a?(Hash)

        begin
          (@engine.services || []).each_with_object({}) do |s, acc|
            h_name = s.respond_to?(:host_name) ? s.host_name : s['host_name']
            desc = s.respond_to?(:description) ? s.description : s['description']
            acc[h_name] ||= {}
            acc[h_name][desc] = { 'description' => desc, 'check_command' => 'check_ping' }
          end
        rescue StandardError
          {}
        end
      end

      def load_timeperiods
        periods = @engine.timeperiods rescue []
        periods.map { |tp| tp.is_a?(Hash) ? tp['name'] : tp.to_s }.to_set
      end
    end
  end
end
