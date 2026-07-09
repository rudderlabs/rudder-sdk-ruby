# frozen_string_literal: true

require 'json'
require 'webrick'

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'rudder/analytics'

class ImmediateBackoffPolicy
  def initialize(intervals)
    @intervals = intervals
  end

  def next_interval
    raise 'ImmediateBackoffPolicy has no intervals left' if @intervals.empty?

    @intervals.shift
  end
end

RSpec.describe 'retry behavior over a local HTTP boundary' do
  def drain_queue(queue)
    items = []
    loop { items << queue.pop(true) }
  rescue ThreadError
    items
  end

  def start_retrying_server(captured_requests)
    request_count = 0
    mutex = Mutex.new
    server = WEBrick::HTTPServer.new(
      :BindAddress => '127.0.0.1',
      :Port => 0,
      :Logger => WEBrick::Log.new($stderr, WEBrick::Log::FATAL),
      :AccessLog => [],
      :DoNotReverseLookup => true
    )

    server.mount_proc('/v1/batch') do |request, response|
      captured_requests << {
        :path => request.path,
        :authorization => request['authorization'],
        :content_type => request['content-type'],
        :content_encoding => request['content-encoding'],
        :body => request.body
      }

      current_request = mutex.synchronize { request_count += 1 }
      if current_request == 1
        response.status = 429
        response.body = 'Too Many Requests'
      else
        response.status = 200
        response['Content-Type'] = 'application/json'
        response.body = '{}'
      end
    end

    server_thread = Thread.new { server.start }
    [server, server_thread, server.listeners.first.addr[1]]
  end

  it 'retries a 429 and resends the same batch through the public API' do
    captured_requests = Queue.new
    captured_errors = Queue.new
    server, server_thread, port = start_retrying_server(captured_requests)

    begin
      analytics = Rudder::Analytics.new(
        :write_key => 'testsecret',
        :data_plane_url => "http://127.0.0.1:#{port}",
        :ssl => false,
        :gzip => false,
        :retries => 2,
        :backoff_policy => ImmediateBackoffPolicy.new([0]),
        :on_error => proc { |status, error| captured_errors << [status, error] }
      )

      analytics.track(
        :user_id => 'user-1',
        :event => 'Retry Contract Event',
        :message_id => 'message-1'
      )
      analytics.flush

      requests = drain_queue(captured_requests)
      errors = drain_queue(captured_errors)

      expect(errors).to be_empty
      expect(requests.length).to eq(2)
      expect(requests[0][:path]).to eq('/v1/batch')
      expect(requests[0][:authorization]).to match(/\ABasic /)
      expect(requests[0][:content_type]).to eq('application/json')
      expect(requests[0][:content_encoding]).to be_nil
      expect(requests[0][:body]).to eq(requests[1][:body])

      payload = JSON.parse(requests[0][:body])
      event = payload['batch'].first

      expect(event['type']).to eq('track')
      expect(event['userId']).to eq('user-1')
      expect(event['event']).to eq('Retry Contract Event')
      expect(event['messageId']).to eq('message-1')
    ensure
      server.shutdown
      server_thread.join(5)
    end
  end
end
