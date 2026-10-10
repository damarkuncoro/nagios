# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::PerfdataParser do
  describe '.parse' do
    it 'parses single-line output with performance data' do
      raw = "PING OK - Packet loss = 0%, RTA = 0.05 ms | rta=0.050ms;100.000;500.000;0; pl=0%;20;60;;"
      res = described_class.parse(raw)

      expect(res.short_output).to eq('PING OK - Packet loss = 0%, RTA = 0.05 ms')
      expect(res.perf_data_string).to eq('rta=0.050ms;100.000;500.000;0; pl=0%;20;60;;')
      expect(res.has_metrics?).to be true
      expect(res.metrics.size).to eq(2)

      rta = res.metric('rta')
      expect(rta.value).to eq(0.05)
      expect(rta.uom).to eq('ms')
      expect(rta.warn).to eq(100.0)
      expect(rta.crit).to eq(500.0)
      expect(rta.status).to eq(:ok)

      pl = res.metric('pl')
      expect(pl.value).to eq(0)
      expect(pl.uom).to eq('%')
      expect(pl.warn).to eq(20)
      expect(pl.crit).to eq(60)
    end

    it 'parses multi-line output with long details' do
      raw = <<~OUTPUT
        DISK WARNING - free space: / 120 MB (4%);
        /dev/sda1 mounted on / (3.8GB used of 4.0GB)
        Inode usage: 45%
        | /=3880MB;3600;3900;0;4000
      OUTPUT

      res = described_class.parse(raw)
      expect(res.short_output).to eq('DISK WARNING - free space: / 120 MB (4%);')
      expect(res.long_output).to include('/dev/sda1 mounted on /')
      expect(res.long_output).to include('Inode usage: 45%')

      metric = res.metric('/')
      expect(metric.value).to eq(3880)
      expect(metric.uom).to eq('MB')
      expect(metric.warn).to eq(3600)
      expect(metric.crit).to eq(3900)
      expect(metric.percentage).to eq(97.0)
      expect(metric.status).to eq(:warning)
      expect(metric.warning?).to be true
    end

    it 'evaluates critical status when metric reaches crit threshold' do
      raw = "HTTP CRITICAL | time=2.5s;1.0;2.0;0;5.0"
      res = described_class.parse(raw)
      m = res.metric('time')
      expect(m.status).to eq(:critical)
      expect(m.critical?).to be true
    end
  end

  describe '.format_template' do
    it 'formats service perfdata in default Nagios template format' do
      formatted = described_class.format_template(
        host_name: 'prod-db-1',
        service_desc: 'CPU Load',
        perf_data_string: 'load1=0.45;2.0;4.0;0;',
        timestamp: 1728551200
      )

      expect(formatted).to include("DATATYPE::SERVICEPERFDATA")
      expect(formatted).to include("TIMET::1728551200")
      expect(formatted).to include("HOSTNAME::prod-db-1")
      expect(formatted).to include("SERVICEDESC::CPU Load")
      expect(formatted).to include("SERVICEPERFDATA::load1=0.45;2.0;4.0;0;")
    end
  end
end
