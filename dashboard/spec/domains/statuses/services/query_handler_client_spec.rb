# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::QueryHandlerClient do
  describe '.query' do
    it 'handles echo query with 200 response' do
      res = described_class.query('echo', 'HELLO_NAGIOS')
      expect(res.success?).to be true
      expect(res.status_code).to eq(200)
      expect(res.body).to eq('HELLO_NAGIOS')
    end

    it 'handles help query listing registered handlers' do
      res = described_class.query('help')
      expect(res.success?).to be true
      expect(res.body).to include('@echo')
      expect(res.body).to include('@core')
    end

    it 'returns 404 for unknown handlers' do
      res = described_class.query('nonexistent_handler')
      expect(res.status_code).to eq(404)
      expect(res.success?).to be false
    end
  end

  describe '.ping' do
    it 'returns true when echo responds successfully' do
      expect(described_class.ping).to be true
    end
  end

  describe '.handlers' do
    it 'returns array of available handlers' do
      handlers = described_class.handlers
      expect(handlers).to be_an(Array)
      expect(handlers.join).to include('@echo')
    end
  end
end
