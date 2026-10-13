# frozen_string_literal: true

require 'fileutils'

module Engines
  # Serializes in-memory monitoring engine runtime state to Nagios status.dat format.
  class StatusDumper
    def self.dump!(target_file:, start_time:, active_workers:, host_states:, service_states:, comments:, downtimes:, notifications_enabled: 1, mutex: nil)
      FileUtils.mkdir_p(File.dirname(target_file))

      serialize_proc = proc do
        snapshot = Statuses::Services::StatusDataParser::StatusSnapshot.new(
          info: {
            'created' => Time.now.to_i,
            'version' => '4.5.14-PureRuby'
          },
          programstatus: {
            'program_start' => start_time.to_i,
            'nagios_pid' => Process.pid,
            'is_currently_running' => 1,
            'total_services' => service_states.values.sum(&:size),
            'total_hosts' => host_states.size,
            'active_workers' => active_workers,
            'notifications_enabled' => notifications_enabled || 1
          },
          hosts: host_states,
          services: service_states,
          contacts: {},
          comments: comments,
          downtimes: downtimes
        )

        content = Statuses::Services::StatusDataParser.serialize(snapshot)
        File.write(target_file, content)
      end

      if mutex
        mutex.synchronize(&serialize_proc)
      else
        serialize_proc.call
      end
    end
  end
end
