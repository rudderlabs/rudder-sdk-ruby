<p align="center">
  <a href="https://rudderstack.com/">
    <img src="https://user-images.githubusercontent.com/59817155/121357083-1c571300-c94f-11eb-8cc7-ce6df13855c9.png">
  </a>
</p>

<p align="center"><b>The Customer Data Platform for Developers</b></p>

<p align="center">
  <b>
    <a href="https://rudderstack.com">Website</a>
    ·
    <a href="https://www.rudderstack.com/docs/sources/event-streams/sdks/rudderstack-ruby-sdk/">Documentation</a>
    ·
    <a href="https://rudderstack.com/join-rudderstack-slack-community">Community Slack</a>
  </b>
</p>

<p align="center"><a href="https://rubygems.org/gems/rudder-sdk-ruby"><img src="https://img.shields.io/gem/v/rudder-sdk-ruby?style=flat"/></a></p>

<p align="center"><a href="https://deepwiki.com/rudderlabs/rudder-sdk-ruby"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"/></a></p>

----

# RudderStack Ruby SDK

The RudderStack Ruby SDK lets you send customer event data from your Ruby applications to your specified destinations.

## SDK setup requirements

- Set up a [RudderStack open source](https://app.rudderstack.com/signup?type=opensource) account.
- Set up a Ruby source in the dashboard.
- Copy the write key and the data plane URL. For more information, refer to the [Ruby SDK documentation](https://www.rudderstack.com/docs/sources/event-streams/sdks/rudderstack-ruby-sdk/#sdk-setup-requirements).

## Installation

To install the RudderStack Ruby SDK, add this line to your application's Gem file:

```ruby
gem 'rudder-sdk-ruby'
```

You can also install the SDK into your environment gems by running the following command:

```ruby
gem install 'rudder-sdk-ruby'
```

## Using the SDK

To use the Ruby SDK, create a client instance as shown:

```ruby
require 'rudder-sdk-ruby'

analytics = Rudder::Analytics.new(
  :write_key => 'WRITE_KEY',
  :data_plane_url => 'DATA_PLANE_URL',
  :gzip => true
)
```

| Make sure to replace `WRITE_KEY` and `DATA_PLANE_URL` in the above snippet with the actual values from your RudderStack dashboard. |
| :--- |

You can then use this client to send the events. A sample `track` call sent using the client is shown below:

```ruby
analytics.track(
  :user_id => '1hKOmRA4GRlm',
  :event => 'Item Sold',
  :properties => { :revenue => 9.95, :shipping => 'Free' }
)
```

## Gzipping requests

The Gzip feature is enabled by default in the Ruby SDK. However, you can disable this feature by setting the `gzip` parameter to false while initializing the SDK:


```ruby
analytics = Rudder::Analytics.new(
  :write_key => 'WRITE_KEY', # required
  :data_plane_url => 'DATA_PLANE_URL',
  :gzip => false, // Set to true to enable Gzip compression
  :on_error => proc { |error_code, error_body, exception, response|
    # defaults to an empty proc
  }
)
```

| Note: Gzip requires `rudder-server` version 1.4 or later. Otherwise, your events might fail. |
| :-----|

## Sending events

Refer to the [RudderStack Ruby SDK documentation](https://www.rudderstack.com/docs/sources/event-streams/sdks/rudderstack-ruby-sdk/) for more information on the supported event types.

## Test queue

Enable the `stub` option while initializing the SDK to stub all the requests, making it easier for you to test with this library.

## License

The RudderStack Ruby SDK is released under the [MIT license](https://github.com/rudderlabs/rudder-sdk-ruby/blob/readme-update/LICENSE).
