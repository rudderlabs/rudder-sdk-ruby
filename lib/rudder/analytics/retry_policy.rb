# frozen_string_literal: true

require 'rudder/analytics/backoff_policy'
require 'rudder/analytics/defaults'
require 'net/http'
require 'net/https'
require 'time'

module Rudder
  class Analytics
    class RetryPolicy
      include Rudder::Analytics::Defaults::Request

      RETRYABLE_ERRORS = [
        Timeout::Error,
        EOFError,
        IOError,
        SocketError,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        Net::ProtocolError,
        OpenSSL::SSL::SSLError
      ].freeze

      attr_reader :backoff_policy, :max_retries

      def self.from_config(config)
        backoff_policy = config.backoff_policy || Rudder::Analytics::BackoffPolicy.new(backoff_options(config))
        new(
          :retries => config.retries.nil? ? RETRIES : config.retries,
          :respect_retry_after => config.respect_retry_after.nil? ? true : config.respect_retry_after,
          :backoff_policy => backoff_policy
        )
      end

      def self.backoff_options(config)
        {
          :min_timeout_ms => config.retry_base_delay || BackoffPolicy::MIN_TIMEOUT_MS,
          :max_timeout_ms => config.max_retry_delay || BackoffPolicy::MAX_TIMEOUT_MS,
          :multiplier => BackoffPolicy::MULTIPLIER,
          :randomization_factor => config.retry_jitter_ratio || BackoffPolicy::RANDOMIZATION_FACTOR
        }
      end

      def initialize(options = {})
        @max_retries = normalize_max_retries(options)
        @respect_retry_after = options.has_key?(:respect_retry_after) ? options[:respect_retry_after] : true
        @backoff_policy = options[:backoff_policy] || Rudder::Analytics::BackoffPolicy.new
      end

      def max_attempts
        @max_retries + 1
      end

      def retryable_status_code?(status_code)
        status_code.zero? || status_code == 429 || (status_code >= 500 && status_code <= 599)
      end

      def retryable_exception?(exception)
        RETRYABLE_ERRORS.any? { |error_class| exception.is_a?(error_class) }
      end

      def retry_delay_in_seconds(headers = {})
        interval = next_backoff_interval(retry_after_delay_in_milliseconds(headers))
        interval.to_f / 1000
      end

      private

      def normalize_max_retries(options)
        if options.has_key?(:max_retries)
          [options[:max_retries].to_i, 0].max
        elsif options.has_key?(:retries)
          [options[:retries].to_i - 1, 0].max
        else
          MAX_RETRIES
        end
      end

      def next_backoff_interval(retry_after_delay)
        if @backoff_policy.method(:next_interval).arity.zero?
          [@backoff_policy.next_interval, retry_after_delay].max
        else
          @backoff_policy.next_interval(retry_after_delay)
        end
      end

      def retry_after_delay_in_milliseconds(headers)
        return 0 unless @respect_retry_after

        value = header_value(headers, 'Retry-After')
        return 0 if value.nil?

        parse_retry_after_delay(value)
      end

      def header_value(headers, name)
        headers.find { |header_name, _| header_name.to_s.casecmp(name).zero? }&.last
      end

      def parse_retry_after_delay(value)
        value = value.to_s.strip
        return value.to_i * 1000 if value.match?(/\A\d+\z/)

        retry_at = Time.httpdate(value)
        [((retry_at - Time.now) * 1000).ceil, 0].max
      rescue ArgumentError
        0
      end
    end
  end
end
