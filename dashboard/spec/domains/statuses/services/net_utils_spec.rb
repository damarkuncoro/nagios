# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::NetUtils do
  describe '.resolve_address' do
    it 'returns IP directly if given an IPv4 string' do
      expect(described_class.resolve_address('127.0.0.1')).to eq('127.0.0.1')
    end

    it 'resolves localhost successfully' do
      ip = described_class.resolve_address('localhost')
      expect(ip).to be_in(['127.0.0.1', '::1'])
    end
  end

  describe '.valid_port?' do
    it 'validates port numbers in range 1-65535' do
      expect(described_class.valid_port?(80)).to be true
      expect(described_class.valid_port?(443)).to be true
      expect(described_class.valid_port?(0)).to be false
      expect(described_class.valid_port?(70000)).to be false
    end
  end

  describe '.tcp_connect' do
    it 'handles connection failures with error and latency' do
      # Connect to an unlikely port on localhost
      res = described_class.tcp_connect('127.0.0.1', 59999, timeout: 0.2)
      expect(res.host).to eq('127.0.0.1')
      expect(res.port).to eq(59999)
      expect(res.latency_ms).to be >= 0.0
    end
  end
end
