# frozen_string_literal: true

require 'spec_helper'

module Rudder
  class Analytics
    include AsyncHelper

    describe Worker do
      # before do
      #   Rudder::Analytics::Transport.stub = true
      # end

      describe '#init' do
        it 'accepts string keys' do
          queue = Queue.new
          config = Configuration.new({ :batch_size => 100, :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
          worker = Rudder::Analytics::Worker.new(queue, config)
          batch = worker.instance_variable_get(:@batch)
          expect(batch.instance_variable_get(:@max_message_count)).to eq(100)
        end
      end

      describe '#run' do
        before :all do
          Rudder::Analytics::Defaults::Request::BACKOFF = 0.1
        end

        after :all do
          Rudder::Analytics::Defaults::Request::BACKOFF = 30.0
        end

        it 'does not error if the request fails' do
          expect do
            Rudder::Analytics::Transport
              .any_instance
              .stub(:send)
              .and_return(Rudder::Analytics::Response.new(-1, 'Unknown error'))

            queue = Queue.new
            queue << {}
            config = Configuration.new({ :batch_size => 100, :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
            worker = Rudder::Analytics::Worker.new(queue, config)
            worker.run

            expect(queue).to be_empty

            Rudder::Analytics::Transport.any_instance.unstub(:send)
          end.to_not raise_error
        end

        it 'executes the error handler if the request is invalid' do
          Rudder::Analytics::Transport
            .any_instance
            .stub(:send)
            .and_return(Rudder::Analytics::Response.new(400, 'Some error'))

          status = error = nil
          on_error = proc do |yielded_status, yielded_error|
            sleep 0.2 # Make this take longer than thread spin-up (below)
            status, error = yielded_status, yielded_error
          end

          queue = Queue.new
          queue << {}
          config = Configuration.new({ :on_error => on_error, :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
          worker = described_class.new(queue, config)

          # This is to ensure that Client#flush doesn't finish before calling
          # the error handler.
          Thread.new { worker.run }
          sleep 0.1 # First give thread time to spin-up.
          sleep 0.01 while worker.is_requesting?

          Rudder::Analytics::Transport.any_instance.unstub(:send)

          expect(queue).to be_empty
          expect(status).to eq(400)
          expect(error).to eq('Some error')
        end

        it 'executes the on_error_with_messages error handler if the request is invalid' do
          Rudder::Analytics::Transport
            .any_instance
            .stub(:send)
            .and_return(Rudder::Analytics::Response.new(400, 'Some error'))

          status = error = data = nil
          on_error_with_messages = proc do |yielded_status, yielded_error, yielded_data|
            sleep 0.2 # Make this take longer than thread spin-up (below)
            status, error, data = yielded_status, yielded_error, yielded_data.dup
          end

          message = { context: { :ip => '127.0.0.1' }, type: 'identify', traits: { email: 'test@test.com' } }
          queue = Queue.new
          queue << message
          config = Configuration.new({ :on_error_with_messages => on_error_with_messages, :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
          worker = described_class.new(queue, config)

          # This is to ensure that Client#flush doesn't finish before calling
          # the error handler.
          Thread.new { worker.run }
          sleep 0.1 # First give thread time to spin-up.
          sleep 0.01 while worker.is_requesting?

          Rudder::Analytics::Transport.any_instance.unstub(:send)

          expect(queue).to be_empty
          expect(status).to eq(400)
          expect(error).to eq('Some error')
          expect(data).to eq([message])
        end

        it 'does not execute error handlers for successful non-200 responses' do
          Rudder::Analytics::Transport
            .any_instance
            .stub(:send)
            .and_return(Rudder::Analytics::Response.new(201, 'Accepted'))

          on_error = proc { raise 'on_error should not be called' }
          on_error_with_messages = proc { raise 'on_error_with_messages should not be called' }
          queue = Queue.new
          queue << {}
          config = Configuration.new({
            :on_error => on_error,
            :on_error_with_messages => on_error_with_messages,
            :write_key => 'write_key',
            :data_plane_url => 'data_plane_url'
          })
          worker = described_class.new(queue, config)

          expect { worker.run }.to_not raise_error

          Rudder::Analytics::Transport.any_instance.unstub(:send)
        end

        # it 'does not call on_error if the request is good' do
        #   on_error = proc do |status, error|
        #     puts "#{status}, #{error}"
        #   end

        #   expect(on_error).to_not receive(:call)

        #   queue = Queue.new
        #   queue << Requested::TRACK
        #   config = Configuration.new({ :on_error => on_error, :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
        #   worker = described_class.new(queue, config)
        #   worker.run

        #   expect(queue).to be_empty
        # end

        # it 'calls on_error for bad json' do
        #   bad_obj = Object.new
        #   def bad_obj.to_json(*_args)
        #     raise "can't serialize to json"
        #   end

        #   on_error = proc {}
        #   expect(on_error).to receive(:call).once.with(-1, /serialize to json/)

        #   good_message = Requested::TRACK
        #   bad_message = Requested::TRACK.merge({ 'bad_obj' => bad_obj })

        #   queue = Queue.new
        #   queue << good_message
        #   queue << bad_message
        #   config = Configuration.new({ :on_error => on_error, :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
        #   worker = described_class.new(queue, config)
        #   worker.run
        #   expect(queue).to be_empty
        # end
      end

      describe '#is_requesting?' do
        it 'does not return true if there isn\'t a current batch' do
          queue = Queue.new
          config = Configuration.new({ :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
          worker = Rudder::Analytics::Worker.new(queue, config)

          expect(worker.is_requesting?).to eq(false)
        end

        it 'returns true if there is a current batch' do
          Rudder::Analytics::Transport
            .any_instance
            .stub(:send) {
              sleep(0.2)
              Rudder::Analytics::Response.new(200, 'Success')
            }

          queue = Queue.new
          queue << Requested::TRACK
          config = Configuration.new({ :write_key => 'write_key', :data_plane_url => 'data_plane_url' })
          worker = Rudder::Analytics::Worker.new(queue, config)

          worker_thread = Thread.new { worker.run }
          eventually { expect(worker.is_requesting?).to eq(true) }

          worker_thread.join
          expect(worker.is_requesting?).to eq(false)

          Rudder::Analytics::Transport.any_instance.unstub(:send)
        end
      end
    end
  end
end
