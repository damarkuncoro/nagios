require 'rails_helper'

RSpec.describe Statuses::ValueObjects::StatusCode do
  it 'maps numeric service status codes' do
    expect(described_class.new(2, type: :service).value).to eq('OK')
    expect(described_class.new(4, type: :service).value).to eq('WARNING')
    expect(described_class.new(8, type: :service).value).to eq('CRITICAL')
  end

  it 'maps numeric host status codes' do
    expect(described_class.new(2, type: :host).value).to eq('UP')
    expect(described_class.new(4, type: :host).value).to eq('DOWN')
  end

  it 'compares equal with string status' do
    code = described_class.new(2, type: :service)
    expect(code == 'OK').to be true
    expect(code == 'WARNING').to be false
  end
end
