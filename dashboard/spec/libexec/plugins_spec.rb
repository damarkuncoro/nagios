# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pure-Ruby Nagios Plugins' do
  let(:libexec_dir) { Rails.root.join('libexec') }

  describe 'check_disk.rb' do
    it 'executes and reports disk usage with valid Nagios exit code' do
      output = `#{libexec_dir}/check_disk.rb -p / -w 99 -c 100`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/DISK OK - .* free \(.*% used\) on \//)
      expect(output).to include('used=')
      expect(output).to include('free=')
    end
  end

  describe 'check_memory.rb' do
    it 'executes and reports memory usage with perfdata' do
      output = `#{libexec_dir}/check_memory.rb -w 99 -c 100`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/MEMORY OK - \d+% used/)
      expect(output).to include('used=')
      expect(output).to include('free=')
    end
  end

  describe 'check_tcp.rb' do
    it 'reports CRITICAL when port is closed or invalid host' do
      output = `#{libexec_dir}/check_tcp.rb -H 127.0.0.1 -p 59999 -c 0.5 2>/dev/null`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/TCP CRITICAL/)
    end
  end
end
