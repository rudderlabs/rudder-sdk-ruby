# frozen_string_literal: true

module Rudder
  class Analytics
    module Defaults
      module Request
        HOST = 'localhost'
        PORT = 8080
        PATH = '/v1/batch'
        HEADERS = { 'Accept' => 'application/json',
                    'Content-Type' => 'application/json',
                    'Content-Encoding' => 'gzip' }
        RETRIES = 10
      end

      module Queue
        MAX_SIZE = 10000
      end

      module Message
        MAX_BYTES = 32768 # 32Kb
      end

      module MessageBatch
        MAX_BYTES = 512_000 # 500Kb
        MAX_SIZE = 100
      end

      module BackoffPolicy
        MIN_TIMEOUT_MS = 100
        MAX_TIMEOUT_MS = 10000
        MULTIPLIER = 1.5
        RANDOMIZATION_FACTOR = 0.5
      end
    end
  end
end
