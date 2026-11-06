require 'rudder-sdk-ruby'
require 'timeout'

raise 'Oj installed in runtime environment' unless Gem::Specification.find_all_by_name('oj').empty?
errors = []
client = Rudder::Analytics.new(:write_key => 'test', :data_plane_url => 'http://localhost',
                               :stub => true, :on_error => proc { |_, error| errors << error })
raise 'event rejected' unless client.track('user_id' => 'test', 'event' => 'runtime smoke')
Timeout.timeout(10) { client.flush }
raise errors.inspect unless errors.empty?
