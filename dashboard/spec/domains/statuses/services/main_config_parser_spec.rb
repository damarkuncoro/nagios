# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::MainConfigParser do
  let(:sample_cfg) do
    <<~CFG
      # Nagios Core Main Configuration File
      log_file=/usr/local/nagios/var/nagios.log
      cfg_file=/usr/local/nagios/etc/objects/commands.cfg
      cfg_file=/usr/local/nagios/etc/objects/contacts.cfg
      cfg_dir=/usr/local/nagios/etc/conf.d
      status_file=/usr/local/nagios/var/status.dat
      status_update_interval=10
      enable_notifications=1
      execute_service_checks=true
      interval_length=60
      low_service_flap_threshold=5.0
      high_service_flap_threshold=20.0
      service_check_timeout=60
    CFG
  end

  describe '#parse' do
    it 'parses scalar and array directives correctly' do
      config = described_class.parse(sample_cfg)

      expect(config['log_file']).to eq('/usr/local/nagios/var/nagios.log')
      expect(config['cfg_file']).to eq([
        '/usr/local/nagios/etc/objects/commands.cfg',
        '/usr/local/nagios/etc/objects/contacts.cfg'
      ])
      expect(config['cfg_dir']).to eq(['/usr/local/nagios/etc/conf.d'])
      expect(config['status_update_interval']).to eq(10)
      expect(config['enable_notifications']).to be true
      expect(config['execute_service_checks']).to be true
      expect(config['interval_length']).to eq(60)
      expect(config['low_service_flap_threshold']).to eq(5.0)
      expect(config['high_service_flap_threshold']).to eq(20.0)
      expect(config['service_check_timeout']).to eq(60)
    end

    it 'ignores commented lines and empty lines' do
      config = described_class.parse("# Comment\n; Semicolon comment\ninterval_length=30\n")
      expect(config['interval_length']).to eq(30)
      expect(config['cfg_file']).to eq([])
    end
  end

  describe '#serialize' do
    it 'serializes config hash back to valid nagios.cfg syntax' do
      original = described_class.parse(sample_cfg)
      serialized = described_class.serialize(original)

      expect(serialized).to include('log_file=/usr/local/nagios/var/nagios.log')
      expect(serialized).to include('cfg_file=/usr/local/nagios/etc/objects/commands.cfg')
      expect(serialized).to include('cfg_file=/usr/local/nagios/etc/objects/contacts.cfg')
      expect(serialized).to include('enable_notifications=1')

      # Roundtrip check
      reparsed = described_class.parse(serialized)
      expect(reparsed['log_file']).to eq(original['log_file'])
      expect(reparsed['cfg_file']).to eq(original['cfg_file'])
      expect(reparsed['enable_notifications']).to eq(original['enable_notifications'])
    end
  end

  describe '#validate' do
    it 'validates correct configurations' do
      config = described_class.parse(sample_cfg)
      result = described_class.new.validate(config)

      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it 'detects invalid flap thresholds when low >= high' do
      invalid_cfg = described_class.parse(sample_cfg)
      invalid_cfg['low_service_flap_threshold'] = 25.0
      invalid_cfg['high_service_flap_threshold'] = 15.0

      result = described_class.new.validate(invalid_cfg)
      expect(result[:valid]).to be false
      expect(result[:errors].first).to include('low_service_flap_threshold')
    end

    it 'detects non-positive timeouts' do
      invalid_cfg = described_class.parse(sample_cfg)
      invalid_cfg['service_check_timeout'] = -5

      result = described_class.new.validate(invalid_cfg)
      expect(result[:valid]).to be false
      expect(result[:errors].first).to include('service_check_timeout')
    end
  end
end
