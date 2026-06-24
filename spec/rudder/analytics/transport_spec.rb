# frozen_string_literal: true

require 'spec_helper'

module Rudder
  class Analytics
    describe Transport do
      subject {
        described_class.new(
          Configuration.new({ :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
        )
      }
      before do
        # Try and keep debug statements out of tests
        allow(subject.logger).to receive(:error)
        allow(subject.logger).to receive(:debug)
      end

      describe '#initialize' do
        let!(:net_http) { Net::HTTP.new(anything, anything) }
        let!(:config) { Configuration.new({ :write_key => 'write_key', :data_plane_url => 'data_plane_url', :ssl => false }) }

        before do
          allow(Net::HTTP).to receive(:new) { net_http }
        end

        it 'sets an initalized Net::HTTP read_timeout' do
          expect(net_http).to receive(:use_ssl=)
          described_class.new(config)
        end

        it 'sets an initalized Net::HTTP read_timeout' do
          expect(net_http).to receive(:read_timeout=)
          described_class.new(config)
        end

        it 'sets an initalized Net::HTTP open_timeout' do
          expect(net_http).to receive(:open_timeout=)
          described_class.new(config)
        end

        it 'sets the http client' do
          expect(subject.instance_variable_get(:@http)).to_not be_nil
        end

        context 'no options are set' do
          it 'sets a default path' do
            path = subject.instance_variable_get(:@path)
            expect(path).to eq(described_class::PATH)
          end

          it 'sets a default retries' do
            retries = subject.instance_variable_get(:@retries)
            expect(retries).to eq(described_class::RETRIES)
          end

          it 'sets a default backoff policy' do
            backoff_policy = subject.instance_variable_get(:@backoff_policy)
            expect(backoff_policy).to be_a(Rudder::Analytics::BackoffPolicy)
          end
        end

        context 'options are given' do
          let(:path) { '/v1/batch' }
          let(:retries) { 10 }
          let(:backoff_policy) { FakeBackoffPolicy.new([1, 2, 3]) }
          let(:config) {
            Configuration.new({
              :backoff_policy => backoff_policy,
              :data_plane_url => 'http://localhost:8080/v1/batch',
              :write_key => 'write_key',
              :retries => retries,
              :ssl => false,
              :gzip => false
            })
          }

          subject { described_class.new(config) }

          it 'sets passed in path' do
            expect(subject.instance_variable_get(:@path)).to eq(path)
          end

          it 'sets passed in retries' do
            expect(subject.instance_variable_get(:@retries)).to eq(retries)
          end

          it 'sets false in ssl' do
            expect(net_http).to receive(:use_ssl=).with(false)
            described_class.new(config)
          end

          it 'sets false in gzip' do
            expect(subject.instance_variable_get(:@gzip)).to eq(false)
          end

          it 'sets passed in backoff backoff policy' do
            expect(subject.instance_variable_get(:@backoff_policy))
              .to eq(backoff_policy)
          end
        end
      end

      describe '#send' do
        def build_response(status_code, response_body = '{}', headers = {})
          response = Net::HTTPResponse.new(1.1, status_code, response_body)
          allow(response).to receive(:body) { response_body }
          headers.each { |name, value| response.add_field(name, value) }
          response
        end

        let(:response) {
          Net::HTTPResponse.new(http_version, status_code, response_body)
        }
        let(:http_version) { 1.1 }
        let(:status_code) { 200 }
        let(:response_body) { {}.to_json }
        let(:write_key) { 'abcdefg' }
        let(:batch) { MessageBatch.new({}) }

        before do
          http = subject.instance_variable_get(:@http)
          allow(http).to receive(:start)
          allow(http).to receive(:request) { response }
          allow(response).to receive(:body) { response_body }
        end

        it 'initalizes a new Net::HTTP::Post with path and default headers' do
          path = subject.instance_variable_get(:@path)
          default_headers = {
            'Content-Type' => 'application/json',
            'Accept' => 'application/json',
            'Content-Encoding' => 'gzip'
          }
          expect(Net::HTTP::Post).to receive(:new).with(
            path, default_headers
          ).and_call_original

          subject.send(write_key, batch)
        end

        it 'adds basic auth to the Net::HTTP::Post' do
          expect_any_instance_of(Net::HTTP::Post).to receive(:basic_auth)
            .with(write_key, nil)

          subject.send(write_key, batch)
        end

        # context 'with a stub' do
        #   before do
        #     allow(described_class).to receive(:stub) { true }
        #   end

        #   it 'returns a 200 response' do
        #     expect(subject.send(write_key, batch).status).to eq(200)
        #   end

        #   it 'has a nil error' do
        #     expect(subject.send(write_key, batch).error).to be_nil
        #   end

        #   it 'logs a debug statement' do
        #     expect(subject.logger).to receive(:debug).with(/stubbed request to/)
        #     subject.send(write_key, batch)
        #   end
        # end

        context 'a real request' do
          RSpec.shared_examples('retried request') do |status_code, body|
            let(:status_code) { status_code }
            let(:body) { body }
            let(:retries) { 4 }
            let(:backoff_policy) { FakeBackoffPolicy.new([1000, 1000, 1000]) }
            let(:config) {
              Configuration.new({
                :backoff_policy => backoff_policy,
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key',
                :retries => retries
              })
            }
            subject {
              described_class.new(config)
            }

            it 'retries the request' do
              expect(subject)
                .to receive(:sleep)
                .exactly(retries - 1).times
                .with(1)
                .and_return(nil)
              subject.send(write_key, batch)
            end
          end

          RSpec.shared_examples('non-retried request') do |status_code, body|
            let(:status_code) { status_code }
            let(:body) { body }
            let(:retries) { 4 }
            let(:backoff) { 1 }
            let(:config) {
              Configuration.new({
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key',
                :retries => retries,
                :backoff => backoff
              })
            }
            subject { described_class.new(config) }

            it 'does not retry the request' do
              expect(subject)
                .to receive(:sleep)
                .never
              subject.send(write_key, batch)
            end
          end

          context 'request is successful' do
            let(:status_code) { 201 }
            let(:error) { {}.to_json }
            it 'returns a response code' do
              expect(subject.send(write_key, batch).status).to eq(status_code)
            end

            it 'returns a nil error' do
              expect(subject.send(write_key, batch).error).to eq(error)
            end
          end

          context 'request results in errorful response' do
            let(:error) { 'this is an error' }
            let(:response_body) { { error: error }.to_json }

            it 'returns the parsed error' do
              expect(subject.send(write_key, batch).error).to eq(response_body)
            end
          end

          context 'a request returns a failure status code' do
            # Server errors must be retried
            it_behaves_like('retried request', 500, '{}')
            it_behaves_like('retried request', 503, '{}')

            # All 4xx errors other than 429 (rate limited) must be retried
            it_behaves_like('retried request', 429, '{}')
            it_behaves_like('non-retried request', 404, '{}')
            it_behaves_like('non-retried request', 400, '{}')
          end

          it 'classifies retryable status codes' do
            expect(subject.__send__(:retryable_status_code?, 0)).to eq(true)
            expect(subject.__send__(:retryable_status_code?, 429)).to eq(true)
            expect(subject.__send__(:retryable_status_code?, 500)).to eq(true)
            expect(subject.__send__(:retryable_status_code?, 599)).to eq(true)
            expect(subject.__send__(:retryable_status_code?, 400)).to eq(false)
            expect(subject.__send__(:retryable_status_code?, 404)).to eq(false)
            expect(subject.__send__(:retryable_status_code?, 422)).to eq(false)
          end

          context 'with retry configuration' do
            let(:backoff_policy) { FakeBackoffPolicy.new([0, 0, 0]) }
            let(:config) {
              Configuration.new({
                :backoff_policy => backoff_policy,
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key',
                :retries => 4,
                :gzip => false
              })
            }
            subject { described_class.new(config) }

            it 'retries 429 until success' do
              http = subject.instance_variable_get(:@http)
              responses = [
                build_response(429, 'Too Many Requests'),
                build_response(200, '{}')
              ]

              expect(http).to receive(:request).twice do
                responses.shift
              end
              expect(subject.send(write_key, batch).status).to eq(200)
            end

            it 'does not retry terminal client errors' do
              http = subject.instance_variable_get(:@http)
              expect(http).to receive(:request).once do
                build_response(400, 'Bad Request')
              end

              response = subject.send(write_key, batch)

              expect(response.status).to eq(400)
            end

            it 'returns the last retryable response after the retry budget is exhausted' do
              config = Configuration.new({
                :backoff_policy => FakeBackoffPolicy.new([0]),
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key',
                :retries => 2,
                :gzip => false
              })
              transport = described_class.new(config)
              http = transport.instance_variable_get(:@http)
              responses = [
                build_response(429, 'Too Many Requests'),
                build_response(429, 'Still Limited')
              ]

              allow(http).to receive(:start)
              expect(http).to receive(:request).twice do
                responses.shift
              end

              response = transport.send(write_key, batch)

              expect(response.status).to eq(429)
              expect(response.error).to eq('Still Limited')
            end

            it 'retries retryable network exceptions' do
              http = subject.instance_variable_get(:@http)
              responses = [Net::OpenTimeout.new('timeout'), build_response(200, '{}')]

              expect(http).to receive(:request).twice do
                response = responses.shift
                raise response if response.is_a?(Exception)

                response
              end

              expect(subject.send(write_key, batch).status).to eq(200)
            end

            it 'resends the same event payload after a 429' do
              message_batch = MessageBatch.new(100)
              message_batch << {
                :type => 'track',
                :userId => 'user-1',
                :event => 'Retry Contract Event',
                :messageId => 'message-1'
              }
              http = subject.instance_variable_get(:@http)
              responses = [
                build_response(429, 'Too Many Requests'),
                build_response(200, '{}')
              ]
              payloads = []

              expect(http).to receive(:request).twice do |_request, payload|
                payloads << payload
                responses.shift
              end

              response = subject.send(write_key, message_batch)
              parsed_payload = JSON.parse(payloads.first)

              expect(response.status).to eq(200)
              expect(payloads.length).to eq(2)
              expect(payloads[0]).to eq(payloads[1])
              expect(parsed_payload['batch'].first['messageId']).to eq('message-1')
              expect(parsed_payload['batch'].first['event']).to eq('Retry Contract Event')
            end
          end

          context 'with Retry-After headers' do
            it 'uses Retry-After as a floor on backoff' do
              config = Configuration.new({
                :backoff_policy => FakeBackoffPolicy.new([100]),
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key'
              })
              transport = described_class.new(config)
              retry_policy = transport.instance_variable_get(:@retry_policy)

              expect(retry_policy.retry_delay_in_seconds({ 'Retry-After' => '2' })).to eq(2)
            end

            it 'does not let Retry-After shorten backoff' do
              config = Configuration.new({
                :backoff_policy => FakeBackoffPolicy.new([1000]),
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key'
              })
              transport = described_class.new(config)
              retry_policy = transport.instance_variable_get(:@retry_policy)

              expect(retry_policy.retry_delay_in_seconds({ 'Retry-After' => '1' })).to eq(1)
            end

            it 'honors Retry-After HTTP dates' do
              retry_at = (Time.now + 2).httpdate
              config = Configuration.new({
                :backoff_policy => FakeBackoffPolicy.new([0]),
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key'
              })
              transport = described_class.new(config)
              retry_policy = transport.instance_variable_get(:@retry_policy)

              expect(retry_policy.retry_delay_in_seconds({ 'Retry-After' => retry_at })).to be >= 1
            end

            it 'can disable Retry-After handling' do
              config = Configuration.new({
                :backoff_policy => FakeBackoffPolicy.new([100]),
                :data_plane_url => 'http://localhost:8080/v1/batch',
                :write_key => 'write_key',
                :respect_retry_after => false
              })
              transport = described_class.new(config)
              retry_policy = transport.instance_variable_get(:@retry_policy)

              expect(retry_policy.retry_delay_in_seconds({ 'Retry-After' => '2' })).to eq(0.1)
            end
          end
        end
      end
    end
  end
end
