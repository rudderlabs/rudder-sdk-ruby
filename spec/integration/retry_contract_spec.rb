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

class RecordingBackoffPolicy
  attr_reader :floors

  def initialize
    @floors = []
  end

  def next_interval(floor_ms = 0)
    @floors << floor_ms
    0
  end
end

RSpec.describe 'retry behavior over a local HTTP boundary' do
  def drain_queue(queue)
    items = []
    loop { items << queue.pop(true) }
  rescue ThreadError
    items
  end

  def start_server(captured_requests, response_sequence)
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
      response_definition = response_sequence.fetch(
        [current_request - 1, response_sequence.length - 1].min
      )

      response.status = response_definition.fetch(:status)
      response.body = response_definition.fetch(:body, '{}')
      response_definition.fetch(:headers, {}).each do |name, value|
        response[name] = value
      end
    end

    server_thread = Thread.new { server.start }
    [server, server_thread, server.listeners.first.addr[1]]
  end

  def exercise_public_api(response_sequence, backoff_policy: ImmediateBackoffPolicy.new([0]), retries: 2)
    captured_requests = Queue.new
    captured_errors = Queue.new
    captured_errors_with_messages = Queue.new
    server, server_thread, port = start_server(captured_requests, response_sequence)

    begin
      analytics = Rudder::Analytics.new(
        :write_key => 'testsecret',
        :data_plane_url => "http://127.0.0.1:#{port}",
        :ssl => false,
        :gzip => false,
        :retries => retries,
        :backoff_policy => backoff_policy,
        :on_error => proc { |status, error| captured_errors << [status, error] },
        :on_error_with_messages => proc do |status, error, messages|
          captured_errors_with_messages << [status, error, messages.map(&:dup)]
        end
      )

      analytics.track(
        :user_id => 'user-1',
        :event => 'Retry Contract Event',
        :message_id => 'message-1'
      )
      analytics.flush

      {
        :requests => drain_queue(captured_requests),
        :errors => drain_queue(captured_errors),
        :errors_with_messages => drain_queue(captured_errors_with_messages)
      }
    ensure
      server.shutdown
      server_thread.join(5)
    end
  end

  def expect_valid_event_request(request)
    expect(request[:path]).to eq('/v1/batch')
    expect(request[:authorization]).to match(/\ABasic /)
    expect(request[:content_type]).to eq('application/json')
    expect(request[:content_encoding]).to be_nil

    event = JSON.parse(request[:body])['batch'].first
    expect(event['type']).to eq('track')
    expect(event['userId']).to eq('user-1')
    expect(event['event']).to eq('Retry Contract Event')
    expect(event['messageId']).to eq('message-1')
  end

  it 'sends an event once when the server returns 200' do
    result = exercise_public_api([{ :status => 200 }])

    expect(result[:requests].length).to eq(1)
    expect_valid_event_request(result[:requests].first)
    expect(result[:errors]).to be_empty
    expect(result[:errors_with_messages]).to be_empty
  end

  it 'does not retry a terminal 404 response' do
    result = exercise_public_api([{ :status => 404, :body => 'Not Found' }])

    expect(result[:requests].length).to eq(1)
    expect(result[:errors]).to eq([[404, 'Not Found']])
    expect(result[:errors_with_messages].length).to eq(1)

    status, error, messages = result[:errors_with_messages].first
    expect(status).to eq(404)
    expect(error).to eq('Not Found')
    expect(messages.first[:messageId]).to eq('message-1')
  end

  it 'retries a 429 and resends the same batch through the public API' do
    response_sequence = [
      { :status => 429, :body => 'Too Many Requests' },
      { :status => 200 }
    ]
    result = exercise_public_api(response_sequence)

    requests = result[:requests]
    expect(result[:errors]).to be_empty
    expect(result[:errors_with_messages]).to be_empty
    expect(requests.length).to eq(2)
    expect(requests[0][:body]).to eq(requests[1][:body])
    expect_valid_event_request(requests.first)
  end

  [500, 501, 502, 503].each do |status_code|
    it "retries a #{status_code} response and succeeds" do
      response_sequence = [
        { :status => status_code, :body => 'Server Error' },
        { :status => 200 }
      ]
      result = exercise_public_api(response_sequence)

      requests = result[:requests]
      expect(requests.length).to eq(2)
      expect(requests[0][:body]).to eq(requests[1][:body])
      expect(result[:errors]).to be_empty
      expect(result[:errors_with_messages]).to be_empty
    end
  end

  it 'returns the final error after the retry budget is exhausted' do
    response_sequence = [
      { :status => 503, :body => 'Unavailable' },
      { :status => 503, :body => 'Still Unavailable' }
    ]
    result = exercise_public_api(response_sequence)

    requests = result[:requests]
    expect(requests.length).to eq(2)
    expect(requests[0][:body]).to eq(requests[1][:body])
    expect(result[:errors]).to eq([[503, 'Still Unavailable']])
    expect(result[:errors_with_messages].length).to eq(1)
    expect(result[:errors_with_messages].first[2].first[:messageId]).to eq('message-1')
  end

  it 'passes Retry-After delay seconds from the HTTP response to the backoff policy' do
    backoff_policy = RecordingBackoffPolicy.new
    result = exercise_public_api(
      [
        { :status => 429, :body => 'Too Many Requests', :headers => { 'Retry-After' => '2' } },
        { :status => 200 }
      ],
      :backoff_policy => backoff_policy
    )

    expect(result[:requests].length).to eq(2)
    expect(backoff_policy.floors).to eq([2000])
    expect(result[:errors]).to be_empty
  end
end
