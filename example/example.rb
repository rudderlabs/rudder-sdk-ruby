# frozen_string_literal: true

require 'rudder-sdk-ruby'
require 'yaml'
require 'date'

def uid
  arr = SecureRandom.random_bytes(16).unpack('NnnnnN')
  arr[2] = (arr[2] & 0x0fff) | 0x4000
  arr[3] = (arr[3] & 0x3fff) | 0x8000
  '%08x-%04x-%04x-%04x-%04x%08x' % arr
end

local_config = YAML.safe_load(File.read('example/local_config.yaml'))

ENV['WRITE_KEY'] = local_config['WRITE_KEY']
ENV['DATA_PLANE_URL'] = local_config['DATA_PLANE_URL']
ENV['LOCAL_DATA_PLANE_URL'] = local_config['LOCAL_DATA_PLANE_URL']

analytics = Rudder::Analytics.new(
  write_key: ENV['WRITE_KEY'],
  data_plane_url: ENV['DATA_PLANE_URL'],
  gzip: true
)

# analytics = Rudder::Analytics.new(
#   :write_key => ENV['WRITE_KEY'],
#   :data_plane_url => ENV['DATA_PLANE_URL'],
#   :gzip => true,
#   :on_error => proc { |status, error|
#     # defaults to an empty proc
#   },
#   :on_error_with_messages => proc { |status, error, messages|
#     # defaults to an empty proc
#   }
# )

properties = {
  :library => {
    :application => 'Rudder Desktop',
    :version => '1.1.0',
    :platform => 'osx'
  }
}

traits = {
  :firstname => 'First',
  :lastname => 'Last',
  :Role => 'Jedi',
  :age => 25
}

user_id = '123456'
anonymous_id = uid

context = {
  :screen => {
    :width => 852,
    :height => 393,
    :density => 3
  },
  :os => {
    :name => 'macOS',
    :version => '2.0.2'
  },
  :locale => 'en-US'
}

# context_with_library = {
#   :screen => {
#     :width => 852,
#     :height => 393,
#     :density => 3
#   },
#   :os => {
#     :name => 'macOS',
#     :version => '2.0.2'
#   },
#   :locale => 'en-US',
#   :library => {
#     :name => 'analytics-random-sdk',
#     :version => '1.0.0.beta.1'
#   }
# }

# t = Thread.new do
analytics.track(
  :event => 'Classroom Deletion',
  :anonymous_id => 'admin',
  :properties => {
    :id => 18,
    :name => 'Math Class 2',
    :created_at => '2023-04-18T09:43:05.227-04:00',
    :updated_at => '2023-04-18T09:43:05.227-04:00',
    :grade_level => 4,
    :provider => 'UserProvided',
    :provider_uid => nil,
    :provider_info => {},
    :school_id => 1,
    :disable_sync => {}
  }
)

analytics.screen(
  :user_id => user_id,
  :name => 'Test Screen',
  :anonymous_id => anonymous_id,
  :properties => properties,
  :context => context
)

analytics.identify(
  user_id: '1hKOmRA4GRlm',
  traits: {
    email: "alex@example.com",
    createdAt: "2023-07-24T00:00:00Z",
    subscribe: true
  },
  context: { ip: '10.81.20.10' }
)

analytics.group(
  :user_id => user_id,
  :group_id => uid,
  :anonymous_id => anonymous_id,
  :traits => traits,
  :context => context
)

analytics.alias(
  :user_id => user_id,
  :previous_id => '654321',
  :context => context
)

analytics.page(
  :user_id => user_id,
  :name => 'Test Page',
  :anonymous_id => anonymous_id,
  :properties => properties,
  :context => context
)
# sleep 10000
# end
# t.join

analytics.flush
