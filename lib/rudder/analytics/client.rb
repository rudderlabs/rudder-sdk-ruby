# frozen_string_literal: true

require 'time'
require 'uri'

require 'rudder/analytics/defaults'
require 'rudder/analytics/logging'
require 'rudder/analytics/utils'
require 'rudder/analytics/worker'
require 'rudder/analytics/defaults'
require 'rudder/analytics/configuration'
require 'rudder/analytics/test_queue'
require 'net/http'

module Rudder
  class Analytics
    class Client
      include Rudder::Analytics::Utils
      include Rudder::Analytics::Logging

      # @param [Hash] opts
      # @option opts [String] :write_key Your project's write_key
      # @option opts [String] :data_plane_url Your data plane URL
      # @option opts [FixNum] :max_queue_size Maximum number of calls to be
      #   remain queued.
      # @option opts [Proc] :on_error Handles error calls from the API.
      # @option opts [Proc] :on_error_with_messages Handles error calls from the API, with failed messages.
      def initialize(opts = {})
        @config = Configuration.new(opts)
        @queue = Queue.new
        @worker_mutex = Mutex.new
        @worker = Worker.new(@queue, @config)
        @worker_thread = nil
        at_exit { @worker_thread && @worker_thread[:should_exit] = true }
      end

      # Synchronously waits until the worker has flushed the queue.
      #
      # Use only for scripts which are not long-running, and will specifically
      # exit
      def flush
        while !@queue.empty? || @worker.is_requesting?
          ensure_worker_running
          sleep(0.1)
        end
      end

      # @!macro common_attrs
      #   @option attrs [String] :anonymous_id ID for a user when you don't know
      #     who they are yet. (optional but you must provide either an
      #     `anonymous_id` or `user_id`)
      #   @option attrs [Hash] :context ({})
      #   @option attrs [Hash] :integrations What integrations this event
      #     goes to (optional)
      #   @option attrs [String] :message_id ID that uniquely
      #     identifies a message across the API. (optional)
      #   @option attrs [Time] :timestamp When the event occurred (optional)
      #   @option attrs [String] :user_id The ID for this user in your database
      #     (optional but you must provide either an `anonymous_id` or `user_id`)
      #   @option attrs [Hash] :options Options such as user traits (optional)

      # Tracks an event
      #
      # @see https://segment.com/docs/sources/server/ruby/#track
      #
      # @param [Hash] attrs
      #
      # @option attrs [String] :event Event name
      # @option attrs [Hash] :properties Event properties (optional)
      # @macro common_attrs
      def track(attrs)
        symbolize_keys! attrs
        enqueue(FieldParser.parse_for_track(attrs))
      end

      # Identifies a user
      #
      # @see https://segment.com/docs/sources/server/ruby/#identify
      #
      # @param [Hash] attrs
      #
      # @option attrs [Hash] :traits User traits (optional)
      # @macro common_attrs
      def identify(attrs)
        # printf("\nInside Identify \n")
        symbolize_keys! attrs
        enqueue(FieldParser.parse_for_identify(attrs))
      end

      # Aliases a user from one id to another
      #
      # @see https://segment.com/docs/sources/server/ruby/#alias
      #
      # @param [Hash] attrs
      #
      # @option attrs [String] :previous_id The ID to alias from
      # @macro common_attrs
      def alias(attrs)
        symbolize_keys! attrs
        enqueue(FieldParser.parse_for_alias(attrs))
      end

      # Associates a user identity with a group.
      #
      # @see https://segment.com/docs/sources/server/ruby/#group
      #
      # @param [Hash] attrs
      #
      # @option attrs [String] :group_id The ID of the group
      # @option attrs [Hash] :traits User traits (optional)
      # @macro common_attrs
      def group(attrs)
        symbolize_keys! attrs
        enqueue(FieldParser.parse_for_group(attrs))
      end

      # Records a page view
      #
      # @see https://segment.com/docs/sources/server/ruby/#page
      #
      # @param [Hash] attrs
      #
      # @option attrs [String] :name Name of the page
      # @option attrs [Hash] :properties Page properties (optional)
      # @macro common_attrs
      def page(attrs)
        symbolize_keys! attrs
        enqueue(FieldParser.parse_for_page(attrs))
      end

      # Records a screen view (for a mobile app)
      #
      # @param [Hash] attrs
      #
      # @option attrs [String] :name Name of the screen
      # @option attrs [Hash] :properties Screen properties (optional)
      # @option attrs [String] :category The screen category (optional)
      # @macro common_attrs
      def screen(attrs)
        symbolize_keys! attrs
        enqueue(FieldParser.parse_for_screen(attrs))
      end

      # @return [Fixnum] number of messages in the queue
      def queued_messages
        @queue.length
      end

      def test_queue
        raise 'Test queue only available when setting :test to true.' unless @config.test

        @test_queue ||= TestQueue.new
      end

      private

      # private: Enqueues the action.
      #
      # returns Boolean of whether the item was added to the queue.
      def enqueue(action)
        # puts action
        # add our request id for tracing purposes
        action[:messageId] ||= uid

        if @config.test
          test_queue << action
          return true
        end

        if @queue.length < @config.max_queue_size
          @queue << action
          ensure_worker_running

          true
        else
          logger.warn(
            'Queue is full, dropping events. The :max_queue_size configuration parameter can be increased to prevent this from happening.'
          )
          false
        end
      end

      # private: Checks that the write_key is properly initialized
      # def check_write_key!
      #   raise ArgumentError, 'Write key must be initialized' if @write_key.nil?
      # end

      # private: Checks that the data_plane_url is properly initialized
      # def check_data_plane_url!
      #   raise ArgumentError, 'Data plane url must be initialized' if @data_plane_url.nil?
      # end

      def ensure_worker_running
        return if worker_running?

        @worker_mutex.synchronize do
          return if worker_running?

          @worker_thread = Thread.new do
            @worker.run
          end
        end
      end

      def worker_running?
        @worker_thread && @worker_thread.alive?
      end
    end
  end
end
