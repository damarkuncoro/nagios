# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::CommentsManager do
  let(:manager) { described_class.new }

  before do
    manager.clear!
  end

  describe '#add_host_comment' do
    it 'creates host comment with auto-assigned ID and default persistence' do
      cmt = manager.add_host_comment(
        host_name: 'srv-db01',
        author: 'nagiosadmin',
        comment_data: 'Investigating high I/O wait',
        entry_type: :user
      )

      expect(cmt).to be_a(Statuses::Services::CommentsManager::CommentEntry)
      expect(cmt.id).to eq(1)
      expect(cmt.host_comment?).to be true
      expect(cmt.service_comment?).to be false
      expect(cmt.user_comment?).to be true
      expect(cmt.persistent).to be true
      expect(manager.all_comments.size).to eq(1)
    end
  end

  describe '#add_service_comment' do
    it 'creates service comment and enables targeted querying' do
      cmt = manager.add_service_comment(
        host_name: 'srv-web01',
        service_desc: 'Nginx Status',
        author: 'sre_dev',
        comment_data: 'SSL cert renewed',
        entry_type: :acknowledgement
      )

      expect(cmt.service_comment?).to be true
      expect(cmt.ack_comment?).to be true
      expect(cmt.service_desc).to eq('Nginx Status')

      found = manager.comments_for('srv-web01', 'Nginx Status')
      expect(found.size).to eq(1)
      expect(found.first.comment_data).to eq('SSL cert renewed')

      expect(manager.comments_for('srv-web01', 'Other Service')).to be_empty
    end
  end

  describe '#delete_comment' do
    it 'deletes comment by ID' do
      cmt = manager.add_host_comment(host_name: 'srv-app01', author: 'ops', comment_data: 'Check logs')
      expect(manager.all_comments.size).to eq(1)

      success = manager.delete_comment(cmt.id)
      expect(success).to be true
      expect(manager.all_comments).to be_empty
    end

    it 'returns false for non-existent comment ID' do
      expect(manager.delete_comment(999)).to be false
    end
  end

  describe '#delete_all_comments_for' do
    it 'deletes all comments for specified host or service' do
      manager.add_host_comment(host_name: 'srv-01', author: 'admin', comment_data: 'c1')
      manager.add_host_comment(host_name: 'srv-01', author: 'admin', comment_data: 'c2')
      manager.add_host_comment(host_name: 'srv-02', author: 'admin', comment_data: 'c3')

      deleted = manager.delete_all_comments_for('srv-01')
      expect(deleted).to eq(2)
      expect(manager.all_comments.size).to eq(1)
      expect(manager.all_comments.first.host_name).to eq('srv-02')
    end
  end
end
