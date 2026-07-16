# frozen_string_literal: true

require 'rudder/analytics/defaults'
require 'rudder/analytics/utils'
require 'rudder/analytics/response'
require 'rudder/analytics/logging'
require 'rudder/analytics/backoff_policy'
require 'rudder/analytics/retry_policy'
require 'net/http'
require 'net/https'
require 'json'
require 'uri'
require 'zlib'

module Rudder
  class Analytics
    class Transport
      include Rudder::Analytics::Defaults::Request
      include Rudder::Analytics::Utils
      include Rudder::Analytics::Logging

      attr_reader :stub

      def initialize(config)
        @stub = config.stub || false
        @path = PATH
        @retry_policy = Rudder::Analytics::RetryPolicy.from_config(config)
        @retries = @retry_policy.max_attempts
        @backoff_policy = @retry_policy.backoff_policy

        uri = URI(config.data_plane_url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = config.ssl.nil? ? true : config.ssl
        http.read_timeout = 8
        http.open_timeout = 4

        @http = http
        @gzip = config.gzip.nil? ? true : config.gzip
      end

      def send(write_key, batch)
        logger.debug("Sending request for #{batch.length} items")

        retries = 0

        loop do
          begin
            response, headers = build_response(write_key, batch)
            return response unless should_retry_request?(response.status, response.error)
            return response unless retries_remaining?(retries)

            retries = retry_request(retries, headers, "status #{response.status}")
          rescue StandardError => e
            return error_response(e) unless retryable_exception?(e)
            return error_response(e) unless retries_remaining?(retries)

            retries = retry_exception(retries, e)
          end
        end
      end

      def shutdown
        @http.finish if @http.started?
      end

      private

      def build_response(write_key, batch)
        status_code, body, headers = send_request(write_key, batch)
        error = body
        logger.debug("Response status code: #{status_code}")
        logger.debug("Response error: #{error}") if error

        [Response.new(status_code, error), headers]
      end

      def retries_remaining?(retries)
        retries < @retry_policy.max_retries
      end

      def retry_request(retries, headers, reason)
        retries += 1
        sleep_before_retry(retries, headers, reason)
        retries
      end

      def retry_exception(retries, exception)
        retries += 1
        reset_connection
        sleep_before_retry(retries, {}, "transport error #{exception.class.name}")
        retries
      end

      def should_retry_request?(status_code, body)
        logger.error(body) if status_code >= 400 && !retryable_status_code?(status_code)

        retryable_status_code?(status_code)
      end

      def retryable_status_code?(status_code)
        @retry_policy.retryable_status_code?(status_code)
      end

      def retryable_exception?(exception)
        @retry_policy.retryable_exception?(exception)
      end

      def sleep_before_retry(retry_number, headers, reason)
        delay = @retry_policy.retry_delay_in_seconds(headers)
        remaining = @retry_policy.max_retries - retry_number
        logger.debug("Retrying request after #{reason} in #{delay}s " \
                     "(attempt #{retry_number} of #{@retry_policy.max_attempts}, #{remaining} retries left)")
        sleep(delay) if delay.positive?
      end

      def error_response(exception)
        logger.error(exception.message)
        exception.backtrace&.each { |line| logger.error(line) }
        Response.new(-1, exception.to_s)
      end

      def reset_connection
        @http.finish if @http.started?
      rescue StandardError
        nil
      end

      def send_request(write_key, batch)
        payload = {
          :batch => batch.messages
        }
        if stub
          logger.debug "stubbed request to #{@path}: " \
            "write key = #{write_key}, batch = #{JSON.generate(payload)}"

          [200, '{}', {}]
        else

          payload, headers = encoded_payload(payload)

          request = Net::HTTP::Post.new(@path, headers)
          request.basic_auth(write_key, nil)
          @http.start unless @http.started? # Maintain a persistent connection
          response = @http.request(request, payload)
          [response.code.to_i, response.body, response_headers(response)]
        end
      end

      def encoded_payload(payload)
        headers = HEADERS.dup

        if @gzip
          gzip = Zlib::GzipWriter.new(StringIO.new)
          gzip << payload.to_json
          payload = gzip.close.string
        else
          headers.delete('Content-Encoding')
          payload = JSON.generate(payload)
        end

        [payload, headers]
      end

      def response_headers(response)
        headers = {}
        response.each_header { |name, value| headers[name] = value }
        headers
      end
    end
  end
end
