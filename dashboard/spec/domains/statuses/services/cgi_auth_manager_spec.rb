# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::CgiAuthManager do
  let(:config) do
    {
      'authorized_for_all_hosts' => 'nagiosadmin,sre_lead',
      'authorized_for_all_services' => 'nagiosadmin,sre_lead',
      'authorized_for_system_commands' => 'nagiosadmin,operator',
      'authorized_for_configuration_information' => 'nagiosadmin',
      'authorized_for_read_only' => 'auditor'
    }
  end

  let(:manager) { described_class.new(config: config) }

  describe '#build_profile' do
    it 'grants full privileges to default admin' do
      profile = manager.build_profile('nagiosadmin')
      expect(profile.admin?).to be true
      expect(profile.authorized_for_system_commands).to be true
      expect(profile.read_only).to be false
    end

    it 'enforces read-only profile for auditor' do
      profile = manager.build_profile('auditor')
      expect(profile.read_only).to be true
      expect(profile.authorized_for_system_commands).to be false
    end
  end

  describe '#authorized_for_host?' do
    it 'authorizes user assigned directly to host' do
      host = { 'name' => 'db01', 'contacts' => 'alice,bob' }

      expect(manager.authorized_for_host?('alice', host)).to be true
      expect(manager.authorized_for_host?('charlie', host)).to be false
      expect(manager.authorized_for_host?('sre_lead', host)).to be true # via all_hosts
    end
  end

  describe '#authorized_for_service?' do
    it 'authorizes user via service contact or parent host contact' do
      host = { 'name' => 'db01', 'contacts' => 'db_admin' }
      service = { 'description' => 'Backup', 'contacts' => 'backup_admin' }

      expect(manager.authorized_for_service?('backup_admin', service, host: host)).to be true
      expect(manager.authorized_for_service?('db_admin', service, host: host)).to be true
      expect(manager.authorized_for_service?('random_user', service, host: host)).to be false
    end
  end

  describe '#can_execute_commands?' do
    it 'checks execution privileges' do
      expect(manager.can_execute_commands?('operator')).to be true
      expect(manager.can_execute_commands?('auditor')).to be false
    end
  end
end
