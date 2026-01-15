# frozen_string_literal: true

module SlackCli
  module Models
    Channel = Data.define(:id, :name, :is_private, :is_im, :is_mpim, :is_archived) do
      def self.from_api(data)
        new(
          id: data['id'],
          name: data['name'] || data['name_normalized'],
          is_private: data['is_private'] || false,
          is_im: data['is_im'] || false,
          is_mpim: data['is_mpim'] || false,
          is_archived: data['is_archived'] || false
        )
      end

      # rubocop:disable Metrics/ParameterLists
      def initialize(id:, name: nil, is_private: false, is_im: false, is_mpim: false, is_archived: false)
        super(
          id: id.to_s.freeze,
          name: name&.freeze,
          is_private: is_private,
          is_im: is_im,
          is_mpim: is_mpim,
          is_archived: is_archived
        )
      end
      # rubocop:enable Metrics/ParameterLists

      def dm?
        is_im || is_mpim
      end

      def public?
        !is_private && !dm?
      end

      def display_name
        return name if name

        case id[0]
        when 'C' then '#channel'
        when 'G' then '#private'
        when 'D' then 'DM'
        else id
        end
      end

      def to_s
        dm? ? display_name : "##{name || id}"
      end
    end
  end
end
