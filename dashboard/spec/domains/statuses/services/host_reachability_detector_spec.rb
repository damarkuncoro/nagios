# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::HostReachabilityDetector do
  describe '.determine_reachability' do
    it 'returns UP when host state is UP regardless of parents' do
      res = described_class.determine_reachability(current_state: 0, parent_states: [1, 2])
      expect(res.up?).to be true
      expect(res.state_name).to eq('UP')
      expect(res.reachability).to eq(:reachable)
    end

    it 'returns DOWN when host fails and has no parents defined (direct connection)' do
      res = described_class.determine_reachability(current_state: 1, parent_states: [])
      expect(res.down?).to be true
      expect(res.state_name).to eq('DOWN')
      expect(res.reachability).to eq(:down_direct)
    end

    it 'returns DOWN when host fails but at least one parent router/switch is UP' do
      parents = [
        { name: 'core-switch-1', status: 0 }, # UP
        { name: 'backup-switch-2', status: 1 } # DOWN
      ]
      res = described_class.determine_reachability(current_state: 1, parent_states: parents)
      expect(res.down?).to be true
      expect(res.state_name).to eq('DOWN')
      expect(res.reachability).to eq(:down_route_available)
      expect(res.available_parents).to include('core-switch-1')
      expect(res.blocking_parents).to include('backup-switch-2')
    end

    it 'returns UNREACHABLE when host fails and all parent paths are down' do
      parents = [
        { name: 'core-switch-1', status: 1 }, # DOWN
        { name: 'backup-switch-2', status: 2 } # UNREACHABLE
      ]
      res = described_class.determine_reachability(current_state: 1, parent_states: parents)
      expect(res.unreachable?).to be true
      expect(res.state_name).to eq('UNREACHABLE')
      expect(res.reachability).to eq(:unreachable_path_blocked)
      expect(res.blocking_parents).to match_array(%w[core-switch-1 backup-switch-2])
    end

    it 'preserves passive UNREACHABLE check results' do
      res = described_class.determine_reachability(current_state: 2, passive: true)
      expect(res.unreachable?).to be true
    end
  end

  describe '.analyze_cluster' do
    it 'differentiates between root-cause down switches and downstream unreachable servers' do
      cluster_map = {
        'gateway' => { name: 'gateway', status: 1, parents: [] }, # Root cause DOWN
        'web-01' => { name: 'web-01', status: 1, parents: ['gateway'] },
        'web-02' => { name: 'web-02', status: 1, parents: ['gateway'] }
      }

      analysis = described_class.analyze_cluster(cluster_map)

      expect(analysis['gateway'].down?).to be true
      expect(analysis['gateway'].reachability).to eq(:down_direct)

      expect(analysis['web-01'].unreachable?).to be true
      expect(analysis['web-01'].blocking_parents).to eq(['gateway'])

      expect(analysis['web-02'].unreachable?).to be true
      expect(analysis['web-02'].blocking_parents).to eq(['gateway'])
    end
  end
end
