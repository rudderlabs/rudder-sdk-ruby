# frozen_string_literal: true

module Rudder
  class Analytics
    # Handles parsing fields according to the RudderStack Spec
    #
    # @see https://www.rudderstack.com/docs/event-spec/standard-events/
    class FieldParser # rubocop:disable Metrics/ClassLength
      class << self
        include Rudder::Analytics::Utils

        # In addition to the common fields, track accepts:
        #
        # - "event"
        # - "properties"
        def parse_for_track(fields)
          common = parse_common_fields(fields)

          event = fields[:event]
          check_presence!(event, 'event')

          common.merge({
            :type => 'track',
            :event => event.to_s
          })
        end

        # In addition to the common fields, identify accepts:
        #
        # - "traits"
        def parse_for_identify(fields)
          common = parse_common_fields(fields)

          # add the traits if present
          if fields[:traits]
            traits = fields[:traits]
            context = common[:context].merge({ :traits => traits })

            common = common.merge({
              :context => context
            })
          end

          common.merge({
            :type => 'identify'
          })
        end

        # In addition to the common fields, alias accepts:
        #
        # - "previous_id"
        def parse_for_alias(fields)
          common = parse_common_fields(fields)

          previous_id = fields[:previous_id]
          check_presence!(previous_id, 'previous_id')
          check_string(previous_id, 'previous_id')

          common.merge({
            :type => 'alias',
            :previousId => previous_id
          })
        end

        # In addition to the common fields, group accepts:
        #
        # - "group_id"
        # - "traits"
        def parse_for_group(fields)
          common = parse_common_fields(fields)

          group_id = fields[:group_id]
          check_presence!(group_id, 'group_id')
          check_string(group_id, 'group_id')

          group_data = {
            :type => 'group',
            :groupId => group_id
          }

          # Add traits if present
          group_data[:traits] = fields[:traits] if fields[:traits]

          common.merge(group_data)
        end

        # In addition to the common fields, page accepts:
        #
        # - "name"
        # - "properties"
        def parse_for_page(fields)
          common = parse_common_fields(fields)

          name = fields[:name] || ''
          properties = common[:properties] || {}
          properties = properties.merge({ :name => name })

          common.merge({
            :type => 'page',
            :name => name,
            :event => name,
            :properties => properties
          })
        end

        # In addition to the common fields, screen accepts:
        #
        # - "name"
        # - "properties"
        def parse_for_screen(fields)
          common = parse_common_fields(fields)

          name = fields[:name]
          properties = common[:properties] || {}
          properties = properties.merge({ :name => name })

          category = fields[:category]

          check_presence!(name, 'name')

          parsed = common.merge({
            :type => 'screen',
            :name => name,
            :event => name,
            :properties => properties
          })

          parsed[:category] = category if category

          parsed
        end

        private

        def parse_common_fields(fields) # rubocop:disable Metrics/AbcSize Metrics/CyclomaticComplexity Metrics/PerceivedComplexity
          check_user_id! fields

          current_time = Time.now.utc
          timestamp = fields[:timestamp] || current_time
          check_timestamp! timestamp

          context = fields[:context] || {}
          delete_library_from_context! context
          add_context! context

          parsed = {
            :context => context,
            :integrations => fields[:integrations] || { :All => true },
            :timestamp => datetime_in_iso8601(timestamp),
            :sentAt => datetime_in_iso8601(current_time),
            :messageId => fields[:message_id] || uid,
            :channel => 'server'
          }

          # add the userId if present
          if fields[:user_id]
            check_string(fields[:user_id], 'user_id')
            parsed = parsed.merge({ :userId => fields[:user_id] })
          end
          # add the anonymousId if present
          if fields[:anonymous_id]
            check_string(fields[:anonymous_id], 'anonymous_id')
            parsed = parsed.merge({ :anonymousId => fields[:anonymous_id] })
          end
          # add the properties if present
          if fields[:properties]
            properties = fields[:properties]
            check_is_hash!(properties, 'properties')
            isoify_dates! properties
            parsed = parsed.merge({ :properties => properties })
          end
          # add the traits if present
          if fields[:traits]
            traits = fields[:traits]
            check_is_hash!(traits, 'traits')
            isoify_dates! traits
            # remove top level traits
            # parsed = parsed.merge({ :traits => traits })
          end
          parsed
        end

        def check_user_id!(fields)
          return unless blank?(fields[:user_id])
          return unless blank?(fields[:anonymous_id])

          raise ArgumentError, 'Must supply either user_id or anonymous_id'
        end

        def check_timestamp!(timestamp)
          raise ArgumentError, 'Timestamp must be a Time' unless timestamp.is_a? Time
        end

        def delete_library_from_context!(context)
          context.delete(:library) if context # rubocop:disable Style/SafeNavigation
        end

        def add_context!(context)
          context[:library] = { :name => 'rudderanalytics-ruby', :version => Rudder::Analytics::VERSION.to_s }
        end

        # private: Ensures that a string is non-empty
        #
        # obj    - String|Number that must be non-blank
        # name   - Name of the validated value
        def check_presence!(obj, name)
          raise ArgumentError, "#{name} must be given" if blank?(obj)
        end

        def blank?(obj)
          obj.nil? || (obj.is_a?(String) && obj.empty?)
        end

        def check_is_hash!(obj, name)
          raise ArgumentError, "#{name} must be a Hash" unless obj.is_a? Hash
        end
      end
    end
  end
end
