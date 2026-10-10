# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::NetworkTopologyBuilder do
  let(:hosts) do
    [
      { name: 'gw-core-01', status: 'UP', address: '10.0.0.1', plugin_output: 'Gateway OK' },
      { name: 'sw-rack-01', status: 'UP', address: '10.0.1.1', plugin_output: 'Switch OK' },
      { name: 'web-node-01', status: 'UP', address: '10.0.1.10', plugin_output: 'Web OK' },
      { name: 'db-node-01', status: 'DOWN', address: '10.0.1.20', plugin_output: 'DB Connection Timeout' }
    ]
  end

  let(:host_objects) do
    {
      'gw-core-01' => { 'parents' => '' },
      'sw-rack-01' => { 'parents' => 'gw-core-01' },
      'web-node-01' => { 'parents' => 'sw-rack-01' },
      'db-node-01' => { 'parents' => 'sw-rack-01' }
    }
  end

  let(:services) do
    [
      { host_name: 'web-node-01', description: 'HTTP', status: 'OK' },
      { host_name: 'web-node-01', description: 'SSL', status: 'OK' },
      { host_name: 'db-node-01', description: 'Postgres', status: 'CRITICAL' }
    ]
  end

  describe '#build' do
    it 'builds connected DAG topology tree with multi-tier depth calculations' do
      graph = described_class.build(
        hosts: hosts,
        services: services,
        host_objects: host_objects
      )

      expect(graph).to be_a(Statuses::Services::NetworkTopologyBuilder::TopologyGraph)
      expect(graph.nodes.size).to eq(4)

      # Gateway should be Tier 1 (root node)
      gw = graph.nodes.find { |n| n.name == 'gw-core-01' }
      expect(gw.tier).to eq(1)
      expect(gw.is_root).to be true
      expect(gw.children).to include('sw-rack-01')

      # Switch should be Tier 2
      sw = graph.nodes.find { |n| n.name == 'sw-rack-01' }
      expect(sw.tier).to eq(2)
      expect(sw.parents).to eq(['gw-core-01'])
      expect(sw.children).to contain_exactly('web-node-01', 'db-node-01')

      # Servers should be Tier 3
      web = graph.nodes.find { |n| n.name == 'web-node-01' }
      expect(web.tier).to eq(3)
      expect(web.total_services).to eq(2)
      expect(web.ok_services).to eq(2)

      db = graph.nodes.find { |n| n.name == 'db-node-01' }
      expect(db.tier).to eq(3)
      expect(db.down?).to be true

      expect(graph.max_depth).to eq(3)
      expect(graph.links).to be_an(Array)
      expect(graph.links.any? { |l| l[:source] == 'sw-rack-01' && l[:target] == 'web-node-01' }).to be true
    end

    it 'handles standalone nodes without parents gracefully' do
      graph = described_class.build(hosts: [{ name: 'standalone-host', status: 'UP' }])
      expect(graph.nodes.size).to eq(1)
      expect(graph.nodes.first.tier).to eq(1)
      expect(graph.nodes.first.is_root).to be true
    end
  end
end
