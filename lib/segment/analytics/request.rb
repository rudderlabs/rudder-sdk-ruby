require 'segment/analytics/defaults'
require 'segment/analytics/response'
require 'segment/analytics/logging'
require 'net/http'
require 'net/https'
require 'json'

module Segment
  module Analytics
    class Request
      include Segment::Analytics::Defaults::Request
      include Segment::Analytics::Logging

      # public: Creates a new request object to send analytics batch
      #
      def initialize(options = {})
        options[:host] ||= HOST
        options[:port] ||= PORT
        options[:ssl] ||= SSL
        options[:headers] ||= HEADERS
        @path = options[:path] || PATH
        @retries = options[:retries] || RETRIES
        @backoff = options[:backoff] || BACKOFF

        http = Net::HTTP.new(options[:host], options[:port])
        http.use_ssl = options[:ssl]
        http.read_timeout = 8
        http.open_timeout = 4

        @http = http
      end

      # public: Posts the secret and batch of messages to the API.
      #
      # returns - Response of the status and error if it exists
      def post(secret, batch)
        status, error = nil, nil
        remaining_retries = @retries
        backoff = @backoff
        headers = { 'Content-Type' => 'application/json', 'accept' => 'application/json' }
        begin
          payload = JSON.generate :secret => secret, :batch => batch
          request = Net::HTTP::Post.new(@path, headers)

          if self.class.stub
            status = 200
            error = nil
            logger.debug "stubbed request to #{@path} with payload #{payload}"
          else
            res = @http.request(request, payload)
            status = res.code.to_i
            body = JSON.parse(res.body)
            error = body["error"]
          end

        rescue Exception => err
          logger.error err.message
          status = -1
          error = "Connection error: #{err}"
          logger.info "retries remaining: #{remaining_retries}"

          unless (remaining_retries -=1).zero?
            sleep(backoff)
            retry
          end
        end

        Response.new status, error
      end

      class << self
        attr_accessor :stub
      end
    end
  end
end
