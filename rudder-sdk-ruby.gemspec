require File.expand_path('../lib/rudder/analytics/version', __FILE__)

Gem::Specification.new do |spec|
  spec.name = 'rudder-sdk-ruby'
  spec.version = Rudder::Analytics::VERSION
  spec.files = Dir.glob('{lib,bin}/**/*')
  spec.require_paths = ['lib']
  spec.bindir = 'bin'
  spec.executables = ['analytics_rudder.rb']
  spec.summary = 'Rudder analytics library'
  spec.description = 'The Rudder ruby analytics library'
  spec.authors = ['Rudder']
  spec.email = 'arnab@rudderstack.com'
  spec.homepage = 'https://github.com/rudderlabs/rudder-sdk-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.0'

  # Used in the executable testing script
  spec.add_development_dependency 'commander', '~> 4.4'

  # Used in specs
  spec.add_development_dependency 'rake', '~> 10.3'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'tzinfo', '1.2.1'
  spec.add_development_dependency 'activesupport', '~> 6.0.2'
  if RUBY_VERSION >= '2.0' && RUBY_PLATFORM != 'java'
    spec.add_development_dependency 'oj', '~> 3.6.2'
  end
  if RUBY_VERSION >= '2.1'
    spec.add_development_dependency 'rubocop', '~> 0.78.0'
  end
  spec.add_development_dependency 'codecov', '~> 0.1.4'
end
