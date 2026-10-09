require 'rails_helper'

RSpec.describe Statuses::ValueObjects::PerformanceData do
  it 'parses disk space output correctly' do
    perf = described_class.new('/=30770MiB', description: 'Root Partition', plugin_output: 'DISK OK - free space: / 25929 MiB (45.73% inode=76%):')
    expect(perf.disk?).to be true
    expect(perf.used_percentage).to eq(54.3)
  end

  it 'parses load average output correctly' do
    perf = described_class.new('', description: 'Current Load', plugin_output: 'OK - load average: 1.26, 0.88, 0.39')
    expect(perf.load?).to be true
    expect(perf.value).to eq({ l1: '1.26', l5: '0.88', l15: '0.39' })
  end

  it 'parses ping RTA output correctly' do
    perf = described_class.new('', description: 'PING', plugin_output: 'PING OK - Packet loss = 0%, RTA = 0.07 ms')
    expect(perf.ping?).to be true
    expect(perf.value).to eq(0.07)
    expect(perf.unit).to eq('ms')
  end
end
