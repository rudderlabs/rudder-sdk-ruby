# frozen_string_literal: true

require 'rudder/analytics/defaults'

module Rudder
  class Analytics
    class BackoffPolicy
      include Rudder::Analytics::Defaults::BackoffPolicy

      # @param [Hash] opts
      # @option opts [Numeric] :min_timeout_ms The minimum backoff timeout
      # @option opts [Numeric] :max_timeout_ms The maximum backoff timeout
      # @option opts [Numeric] :multiplier The value to multiply the current
      #   interval with for each retry attempt
      # @option opts [Numeric] :randomization_factor The randomization factor
      #   to use to create a range around the retry interval
      def initialize(opts = {})
        @min_timeout_ms = [opts[:min_timeout_ms] || MIN_TIMEOUT_MS, 0].max
        @max_timeout_ms = [opts[:max_timeout_ms] || MAX_TIMEOUT_MS, 0].max
        @multiplier = [opts[:multiplier] || MULTIPLIER, 0].max
        @randomization_factor = [[opts[:randomization_factor] || RANDOMIZATION_FACTOR, 0].max, 1].min

        @attempts = 0
      end

      # @return [Numeric] the next backoff interval, in milliseconds.
      def next_interval(floor_ms = 0)
        interval = [@min_timeout_ms * (@multiplier**@attempts), @max_timeout_ms].min
        interval = [interval, floor_ms].max
        interval = add_jitter(interval, @randomization_factor)

        @attempts += 1
        interval
      end

      private

      def add_jitter(base, randomization_factor)
        return base if base <= 0 || randomization_factor <= 0

        base + (rand * base * randomization_factor)
      end
    end
  end
end
