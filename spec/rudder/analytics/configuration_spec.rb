# frozen_string_literal: true

require 'spec_helper'

module Rudder
  class Analytics
    describe Configuration do
      subject {
        described_class.new(
          :write_key => 'write_key',
          :data_plane_url => 'data_plane_url',
          :retries => 4
        )
      }

      it 'keeps retries as the public retry budget setting' do
        expect(subject.retries).to eq(4)
      end

      it 'does not expose max_retries as a separate configuration setting' do
        expect(subject).to_not respond_to(:max_retries)
      end
    end
  end
end
