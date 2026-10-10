# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe Statuses::Services::CgiConfigParser do
  let(:parser) { described_class.new }

  let(:sample_content) do
    <<~CFG
      # Sample Nagios cgi.cfg
      main_config_file=/etc/nagios/nagios.cfg
      physical_html_path=/usr/local/nagios/share
      url_html_path=/nagios
      use_authentication=1
      use_ssl_authentication=0
      show_context_help=1
      refresh_rate=30
      result_limit=100

      authorized_for_system_information=nagiosadmin, sreadmin
      authorized_for_system_commands=nagiosadmin, operator
      authorized_for_all_hosts=nagiosadmin, *
      authorized_for_read_only=auditor
    CFG
  end

  describe '#parse' do
    it 'parses scalar, boolean, integer, and list directives' do
      parser.parse(sample_content)

      expect(parser.main_config_file).to eq('/etc/nagios/nagios.cfg')
      expect(parser.authentication_enabled?).to be true
      expect(parser['use_ssl_authentication']).to be false
      expect(parser['show_context_help']).to be true
      expect(parser.refresh_rate).to eq(30)
      expect(parser.result_limit).to eq(100)

      expect(parser.contacts_authorized_for('system_information')).to eq(%w[nagiosadmin sreadmin])
      expect(parser.contacts_authorized_for('system_commands')).to eq(%w[nagiosadmin operator])
      expect(parser.contacts_authorized_for('read_only')).to eq(%w[auditor])
    end

    it 'checks user authorization using wildcards and explicit lists' do
      parser.parse(sample_content)

      expect(parser.user_authorized_for?('sreadmin', 'system_information')).to be true
      expect(parser.user_authorized_for?('random_user', 'system_information')).to be false
      expect(parser.user_authorized_for?('any_user', 'all_hosts')).to be true # wildcard *
    end

    it 'validates directives and emits warnings' do
      parser.parse('use_authentication=1')
      val = parser.validate

      expect(val[:valid]).to be true
      expect(val[:warnings]).to include('No contacts authorized for system_information')
    end

    it 'serializes back to cgi.cfg format' do
      parser.parse(sample_content)
      serialized = parser.to_cfg

      expect(serialized).to include('main_config_file=/etc/nagios/nagios.cfg')
      expect(serialized).to include('refresh_rate=30')
      expect(serialized).to include('use_authentication=1')
    end
  end

  describe '.format_interval' do
    it 'formats duration in seconds into standard Nagios interval string' do
      expect(described_class.format_interval(0)).to eq('0d 0h 0m 0s')
      expect(described_class.format_interval(65)).to eq('0d 0h 1m 5s')
      expect(described_class.format_interval(3665)).to eq('0d 1h 1m 5s')
      expect(described_class.format_interval(90_061)).to eq('1d 1h 1m 1s')
    end
  end

  describe '.format_date' do
    it 'formats timestamps into selected formats' do
      t = Time.utc(2023, 11, 15, 5, 13, 20)
      expect(described_class.format_date(t, format: :iso8601)).to eq('2023-11-15 05:13:20')
      expect(described_class.format_date(t, format: :us)).to eq('11-15-2023 05:13:20')
      expect(described_class.format_date(t, format: :euro)).to eq('15-11-2023 05:13:20')
    end
  end

  describe '.sanitize_output' do
    it 'strips script tags and unescapes newlines' do
      raw = 'CRITICAL: Alert\\n<script>alert(1)</script>Check failed'
      clean = described_class.sanitize_output(raw)

      expect(clean).to eq("CRITICAL: Alert\nCheck failed")
    end
  end
end
