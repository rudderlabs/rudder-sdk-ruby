# frozen_string_literal: true

require 'rudder/analytics/utils'

module Rudder
  class Analytics
    class Configuration
      include Rudder::Analytics::Utils

      attr_reader :write_key, :data_plane_url, :on_error, :on_error_with_messages, :stub, :gzip, :ssl, :batch_size,
                  :test, :max_queue_size, :backoff_policy, :retries, :retry_base_delay, :max_retry_delay,
                  :retry_jitter_ratio, :respect_retry_after

      def initialize(settings = {})
        symbolized_settings = symbolize_keys(settings)

        @test = symbolized_settings[:test]
        @write_key = symbolized_settings[:write_key]
        @data_plane_url = symbolized_settings[:data_plane_url]
        @max_queue_size = symbolized_settings[:max_queue_size] || Defaults::Queue::MAX_SIZE
        @ssl = symbolized_settings[:ssl]
        @on_error = symbolized_settings[:on_error] || proc { |status, error| }
        @on_error_with_messages = symbolized_settings[:on_error_with_messages] || proc { |status, error, messages| }
        @stub = symbolized_settings[:stub]
        @batch_size = symbolized_settings[:batch_size] || Defaults::MessageBatch::MAX_SIZE
        @gzip = symbolized_settings[:gzip]
        @backoff_policy = symbolized_settings[:backoff_policy]
        configure_retry(symbolized_settings)
        raise ArgumentError, 'Missing required option :write_key' \
          unless @write_key
        raise ArgumentError, 'Data plane url must be initialized' \
          unless @data_plane_url
      end

      private

      def configure_retry(settings)
        @retries = settings[:retries]
        @retry_base_delay = normalize_non_negative_integer(settings[:retry_base_delay])
        @max_retry_delay = normalize_non_negative_integer(
          settings[:max_retry_delay] || settings[:maximum_backoff_duration]
        )
        @retry_jitter_ratio = normalize_jitter_ratio(settings[:retry_jitter_ratio])
        @respect_retry_after = normalize_respect_retry_after(settings)
      end

      def normalize_non_negative_integer(value)
        return nil if value.nil?

        [value.to_i, 0].max
      end

      def normalize_jitter_ratio(value)
        return nil if value.nil?

        [[value.to_f, 0.0].max, 1.0].min
      end

      def normalize_respect_retry_after(settings)
        return nil unless settings.has_key?(:respect_retry_after)

        settings[:respect_retry_after] ? true : false
      end
    end
  end
end
