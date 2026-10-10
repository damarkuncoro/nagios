# frozen_string_literal: true

module Statuses
  module Services
    # Adopts comment management and data structures from common/comments.c
    # Tracks user, downtime, flapping, and acknowledgement comments with
    # auto-increment IDs, persistence flags, and broker event notifications.
    class CommentsManager
      CommentEntry = Struct.new(
        :id,
        :type,
        :host_name,
        :service_desc,
        :entry_type,
        :author,
        :comment_data,
        :entry_time,
        :persistent,
        keyword_init: true
      ) do
        def host_comment?
          type == :host
        end

        def service_comment?
          type == :service
        end

        def user_comment?
          entry_type == :user
        end

        def ack_comment?
          entry_type == :acknowledgement
        end

        def downtime_comment?
          entry_type == :downtime
        end

        def flapping_comment?
          entry_type == :flapping
        end
      end

      ENTRY_TYPES = {
        user: 1,
        downtime: 2,
        flapping: 3,
        acknowledgement: 4
      }.freeze

      class << self
        def instance
          @instance ||= new
        end

        def add_host_comment(**args)
          instance.add_host_comment(**args)
        end

        def add_service_comment(**args)
          instance.add_service_comment(**args)
        end

        def delete_comment(comment_id)
          instance.delete_comment(comment_id)
        end

        def delete_all_comments_for(host_name, service_desc = nil)
          instance.delete_all_comments_for(host_name, service_desc)
        end

        def comments_for(host_name, service_desc = nil)
          instance.comments_for(host_name, service_desc)
        end

        def all_comments
          instance.all_comments
        end

        def clear!
          instance.clear!
        end
      end

      attr_reader :comments

      def initialize(broker: Statuses::Events::Broker, logger: DaemonLogger)
        @broker = broker
        @logger = logger
        @comments = {}
        @next_id = 1
        @mutex = Mutex.new
      end

      # Adds host comment (common/comments.c: add_comment)
      def add_host_comment(host_name:, author:, comment_data:, persistent: true, entry_type: :user, entry_time: nil)
        add_entry(
          type: :host,
          host_name: host_name,
          service_desc: nil,
          entry_type: entry_type,
          author: author,
          comment_data: comment_data,
          persistent: persistent,
          entry_time: entry_time
        )
      end

      # Adds service comment (common/comments.c: add_comment)
      def add_service_comment(host_name:, service_desc:, author:, comment_data:, persistent: true, entry_type: :user, entry_time: nil)
        add_entry(
          type: :service,
          host_name: host_name,
          service_desc: service_desc,
          entry_type: entry_type,
          author: author,
          comment_data: comment_data,
          persistent: persistent,
          entry_time: entry_time
        )
      end

      # Deletes comment by ID (common/comments.c: delete_comment)
      def delete_comment(comment_id)
        id = comment_id.to_i
        @mutex.synchronize do
          cmt = @comments.delete(id)
          return false unless cmt

          emit_event(:comment_deleted, cmt)
          @logger.format_entry("COMMENT DELETED: ID ##{id} on #{cmt.host_name}#{cmt.service_desc ? '/' + cmt.service_desc : ''}")
          true
        end
      end

      # Deletes all comments for target host/service (common/comments.c: delete_all_comments)
      def delete_all_comments_for(host_name, service_desc = nil)
        deleted_count = 0
        @mutex.synchronize do
          to_delete = @comments.values.select do |c|
            c.host_name == host_name && (service_desc.nil? ? c.host_comment? : c.service_desc == service_desc)
          end

          to_delete.each do |c|
            @comments.delete(c.id)
            deleted_count += 1
            emit_event(:comment_deleted, c)
          end
        end
        deleted_count
      end

      def comments_for(host_name, service_desc = nil)
        @mutex.synchronize do
          @comments.values.select do |c|
            c.host_name == host_name && (service_desc.nil? ? c.host_comment? : c.service_desc == service_desc)
          end
        end
      end

      def all_comments
        @mutex.synchronize { @comments.values }
      end

      def clear!
        @mutex.synchronize { @comments.clear }
      end

      private

      def add_entry(**params)
        @mutex.synchronize do
          id = @next_id
          @next_id += 1

          ts = (params[:entry_time] || current_timestamp).to_i

          cmt = CommentEntry.new(
            id: id,
            type: params[:type],
            host_name: params[:host_name],
            service_desc: params[:service_desc],
            entry_type: params[:entry_type] || :user,
            author: params[:author].to_s,
            comment_data: params[:comment_data].to_s,
            entry_time: ts,
            persistent: params[:persistent] != false
          )

          @comments[id] = cmt
          emit_event(:comment_added, cmt)
          @logger.format_entry("COMMENT ADDED: ID ##{id} by #{cmt.author} on #{cmt.host_name}#{cmt.service_desc ? '/' + cmt.service_desc : ''}")
          cmt
        end
      end

      def emit_event(event_type, comment)
        return unless @broker.respond_to?(:publish)

        @broker.publish(
          event_type,
          {
            comment_id: comment.id,
            host_name: comment.host_name,
            service_desc: comment.service_desc,
            author: comment.author,
            comment_data: comment.comment_data,
            entry_type: comment.entry_type
          },
          source: 'comments_manager'
        )
      rescue StandardError
        # Non-fatal event publishing
      end

      def current_timestamp
        (Time.respond_to?(:current) ? Time.current : Time.now).to_i
      end
    end
  end
end
