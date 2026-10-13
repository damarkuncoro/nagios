# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Discovery Management', type: :request do
  describe 'GET /discovery' do
    it 'renders the discovery index page with 200 OK' do
      get discovery_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Network Autodiscovery')
      expect(response.body).to include('Target Subnet CIDR')
    end
  end

  describe 'POST /discovery/scan' do
    it 'scans subnet and renders result table' do
      post scan_discovery_path, params: { cidr: '127.0.0.1/32', timeout: 0.2 }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Hasil Pemindaian Subnet')
    end
  end

  describe 'POST /discovery/import' do
    let(:tmp_cfg) { Rails.root.join('tmp/test_import_req.cfg').to_s }

    before do
      File.write(tmp_cfg, "# test cfg\n")
      allow(Discovery::Services::DeviceImporter).to receive(:new).and_return(
        Discovery::Services::DeviceImporter.new(cfg_path: tmp_cfg)
      )
    end

    after { File.unlink(tmp_cfg) rescue nil }

    it 'imports discovered device into Nagios configuration' do
      post import_discovery_path, params: {
        ip: '192.168.1.100',
        hostname: 'sw-core-01',
        vendor: 'Cisco',
        device_type: 'Switch',
        open_ports: '22/SSH,80/HTTP'
      }, headers: { "Host" => "localhost" }

      expect(response).to redirect_to(discovery_path(cidr: nil))
      expect(flash[:notice]).to include("successfully added to Nagios monitoring")
    end
  end

  describe 'GET /discovery/interfaces' do
    it 'returns JSON response of interfaces' do
      get interfaces_discovery_path, params: { ip: '127.0.0.1' }, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['ip']).to eq('127.0.0.1')
      expect(json).to have_key('interfaces')
    end
  end
end
