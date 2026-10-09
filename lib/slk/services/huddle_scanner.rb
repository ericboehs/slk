# frozen_string_literal: true

module Slk
  module Services
    # Groups a users.list roster into active huddles.
    #
    # Slack has no list-huddles method. A profile's huddle_state is
    # `in_a_huddle` while they are in one, and huddle_state_call_id is the
    # shared key. A missing call id is not evidence two people share a call,
    # so those profiles stay separate. Disagreeing channel ids are dropped
    # rather than labeling the call with one of them.
    class HuddleScanner
      IN_HUDDLE = 'in_a_huddle'

      def self.group(members)
        new(members).group
      end

      # People who are not in a huddle are useless to the scan and expensive
      # to keep. Drop them as each page arrives.
      def self.keep(members)
        members.select { |member| in_huddle?(member) && member['id'] }
      end

      def self.in_huddle?(member)
        member.dig('profile', 'huddle_state') == IN_HUDDLE
      end

      def initialize(members)
        @members = members
      end

      def group
        huddles.sort_by { |huddle| sort_key(huddle) }
      end

      private

      def huddles
        active.group_by { |member| group_key(member) }.map { |key, people| build(key, people) }
      end

      def active
        self.class.keep(@members)
      end

      def group_key(member)
        call_id(member) || [:solo, member['id']]
      end

      def build(key, people)
        Models::Huddle.new(
          call_id: call_id_for(key),
          channel_id: shared_channel_id(people),
          channel: nil,
          participants: sorted_participants(people)
        )
      end

      def call_id_for(key)
        key.is_a?(Array) ? nil : key
      end

      def shared_channel_id(people)
        ids = people.filter_map { |member| channel_id(member) }.uniq
        ids.first if ids.one?
      end

      def sorted_participants(people)
        people.map { |member| participant(member) }.sort_by { |person| [person.name.downcase, person.id] }
      end

      def participant(member)
        Models::HuddleParticipant.new(id: member['id'], name: participant_name(member))
      end

      def participant_name(member)
        profile = member['profile'] || {}
        names = [profile['display_name'], profile['real_name'], member['real_name'], member['name'], member['id']]
        names.find { |value| !value.to_s.empty? }.to_s
      end

      def call_id(member)
        present(member.dig('profile', 'huddle_state_call_id'))
      end

      def channel_id(member)
        present(member.dig('profile', 'huddle_state_channel_id'))
      end

      def present(value)
        text = value.to_s
        text.empty? ? nil : text
      end

      def sort_key(huddle)
        [-huddle.participants.size, huddle.participants.first.name.downcase, huddle.call_id.to_s]
      end
    end
  end
end
