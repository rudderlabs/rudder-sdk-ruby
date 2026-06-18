# frozen_string_literal: true

require 'rudder/analytics/defaults'
require 'rudder/analytics/message_batch'
require 'rudder/analytics/transport'
require 'rudder/analytics/utils'

module Rudder
  class Analytics
    class Worker
      include Rudder::Analytics::Utils
      include Rudder::Analytics::Defaults
      include Rudder::Analytics::Logging

      # public: Creates a new worker
      #
      # The worker continuously takes messages off the queue
      # and makes requests to the segment.io api
      #
      # queue   - Queue synchronized between client and worker
      # write_key  - String of the project's Write key
      # options - Hash of worker options
      #           batch_size - Fixnum of how many items to send in a batch
      #           on_error   - Proc of what to do on an error
      #
      def initialize(queue, config)
        @queue = queue
        @data_plane_url = config.data_plane_url
        @write_key = config.write_key
        @ssl = config.ssl
        @on_error = config.on_error
        @on_error_with_messages = config.on_error_with_messages
        @batch = MessageBatch.new(config.batch_size)
        @lock = Mutex.new
        @transport = Transport.new(config)
      end

      # public: Continuously runs the loop to check for new events
      #
      def run
        until Thread.current[:should_exit]
          return if @queue.empty?

          @lock.synchronize do
            consume_message_from_queue! until @batch.full? || @queue.empty?
          end

          # res = Request.new(:data_plane_url => @data_plane_url, :ssl => @ssl).post @write_key, @batch
          res = @transport.send @write_key, @batch
          unless success_status?(res.status)
            @on_error.call(res.status, res.error)
            @on_error_with_messages.call(res.status, res.error, @batch.messages)
          end

          @lock.synchronize { @batch.clear }
        end
      ensure
        @transport.shutdown
      end

      # public: Check whether we have outstanding requests.
      #
      def is_requesting?
        @lock.synchronize { !@batch.empty? }
      end

      private

      def success_status?(status)
        status >= 200 && status < 300
      end

      def consume_message_from_queue!
        @batch << @queue.pop
      rescue MessageBatch::JSONGenerationError => e
        @on_error.call(-1, e.to_s)
        @on_error_with_messages.call(-1, e.to_s, [])
      end
    end
  end
end
