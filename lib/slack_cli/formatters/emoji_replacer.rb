# frozen_string_literal: true

module SlackCli
  module Formatters
    # Replaces :emoji: codes with unicode characters
    class EmojiReplacer
      EMOJI_REGEX = /:([a-zA-Z0-9_+-]+):/
      SKIN_TONE_REGEX = /::skin-tone-(\d)/

      # Common emoji mappings (subset - full list would be much larger)
      EMOJI_MAP = {
        # Faces
        'smile' => "\u{1F604}", 'grinning' => "\u{1F600}", 'joy' => "\u{1F602}",
        'rofl' => "\u{1F923}", 'smiley' => "\u{1F603}", 'sweat_smile' => "\u{1F605}",
        'laughing' => "\u{1F606}", 'wink' => "\u{1F609}", 'blush' => "\u{1F60A}",
        'yum' => "\u{1F60B}", 'sunglasses' => "\u{1F60E}", 'heart_eyes' => "\u{1F60D}",
        'kissing_heart' => "\u{1F618}", 'thinking' => "\u{1F914}", 'thinking_face' => "\u{1F914}",
        'raised_eyebrow' => "\u{1F928}", 'neutral_face' => "\u{1F610}", 'expressionless' => "\u{1F611}",
        'unamused' => "\u{1F612}", 'rolling_eyes' => "\u{1F644}", 'grimacing' => "\u{1F62C}",
        'relieved' => "\u{1F60C}", 'pensive' => "\u{1F614}", 'sleepy' => "\u{1F62A}",
        'sleeping' => "\u{1F634}", 'sob' => "\u{1F62D}", 'cry' => "\u{1F622}",
        'scream' => "\u{1F631}", 'angry' => "\u{1F620}", 'rage' => "\u{1F621}",

        # Gestures
        'wave' => "\u{1F44B}", '+1' => "\u{1F44D}", '-1' => "\u{1F44E}",
        'thumbsup' => "\u{1F44D}", 'thumbsdown' => "\u{1F44E}",
        'clap' => "\u{1F44F}", 'raised_hands' => "\u{1F64C}", 'pray' => "\u{1F64F}",
        'point_up' => "\u{261D}", 'point_down' => "\u{1F447}", 'point_left' => "\u{1F448}",
        'point_right' => "\u{1F449}", 'ok_hand' => "\u{1F44C}", 'v' => "\u{270C}",
        'muscle' => "\u{1F4AA}", 'fist' => "\u{270A}",

        # Hearts
        'heart' => "\u{2764}", 'hearts' => "\u{2665}", 'yellow_heart' => "\u{1F49B}",
        'green_heart' => "\u{1F49A}", 'blue_heart' => "\u{1F499}", 'purple_heart' => "\u{1F49C}",
        'black_heart' => "\u{1F5A4}", 'broken_heart' => "\u{1F494}", 'sparkling_heart' => "\u{1F496}",

        # Objects
        'fire' => "\u{1F525}", 'star' => "\u{2B50}", 'sparkles' => "\u{2728}",
        'boom' => "\u{1F4A5}", 'zap' => "\u{26A1}", 'sunny' => "\u{2600}",
        'cloud' => "\u{2601}", 'umbrella' => "\u{2614}", 'snowflake' => "\u{2744}",
        'rocket' => "\u{1F680}", 'airplane' => "\u{2708}", 'car' => "\u{1F697}",
        'gift' => "\u{1F381}", 'trophy' => "\u{1F3C6}", 'medal' => "\u{1F3C5}",
        'bell' => "\u{1F514}", 'key' => "\u{1F511}", 'lock' => "\u{1F512}",
        'bulb' => "\u{1F4A1}", 'book' => "\u{1F4D6}", 'pencil' => "\u{270F}",
        'memo' => "\u{1F4DD}", 'computer' => "\u{1F4BB}", 'phone' => "\u{1F4F1}",
        'camera' => "\u{1F4F7}", 'headphones' => "\u{1F3A7}", 'microphone' => "\u{1F3A4}",

        # Food
        'coffee' => "\u{2615}", 'tea' => "\u{1F375}", 'beer' => "\u{1F37A}",
        'wine_glass' => "\u{1F377}", 'pizza' => "\u{1F355}", 'hamburger' => "\u{1F354}",
        'cake' => "\u{1F370}", 'cookie' => "\u{1F36A}", 'apple' => "\u{1F34E}",
        'banana' => "\u{1F34C}", 'taco' => "\u{1F32E}", 'burrito' => "\u{1F32F}",
        'knife_fork_plate' => "\u{1F37D}",

        # Nature
        'dog' => "\u{1F436}", 'cat' => "\u{1F431}", 'mouse' => "\u{1F42D}",
        'rabbit' => "\u{1F430}", 'bear' => "\u{1F43B}", 'panda_face' => "\u{1F43C}",
        'chicken' => "\u{1F414}", 'penguin' => "\u{1F427}", 'bird' => "\u{1F426}",
        'fish' => "\u{1F41F}", 'bug' => "\u{1F41B}", 'bee' => "\u{1F41D}",
        'rose' => "\u{1F339}", 'sunflower' => "\u{1F33B}", 'tree' => "\u{1F333}",
        'cactus' => "\u{1F335}", 'palm_tree' => "\u{1F334}",

        # Symbols
        'white_check_mark' => "\u{2705}", 'heavy_check_mark' => "\u{2714}",
        'x' => "\u{274C}", 'heavy_multiplication_x' => "\u{2716}",
        'warning' => "\u{26A0}", 'no_entry' => "\u{26D4}", 'sos' => "\u{1F198}",
        'question' => "\u{2753}", 'exclamation' => "\u{2757}", 'bangbang' => "\u{203C}",
        '100' => "\u{1F4AF}", '1234' => "\u{1F522}",

        # Status-related
        'house' => "\u{1F3E0}", 'office' => "\u{1F3E2}", 'hospital' => "\u{1F3E5}",
        'calendar' => "\u{1F4C5}", 'date' => "\u{1F4C5}", 'spiral_calendar' => "\u{1F5D3}",
        'clock1' => "\u{1F550}", 'hourglass' => "\u{231B}", 'stopwatch' => "\u{23F1}",
        'zzz' => "\u{1F4A4}", 'speech_balloon' => "\u{1F4AC}", 'thought_balloon' => "\u{1F4AD}",

        # Common Slack custom
        'party-blob' => "\u{1F389}", 'blob-wave' => "\u{1F44B}",
        'tada' => "\u{1F389}", 'confetti_ball' => "\u{1F38A}",
        'balloon' => "\u{1F388}", 'party_popper' => "\u{1F389}",
        'eyes' => "\u{1F440}", 'eye' => "\u{1F441}",
        'ear' => "\u{1F442}", 'nose' => "\u{1F443}",
        'brb' => "\u{1F6B6}", 'away' => "\u{1F6B6}",
        'test_tube' => "\u{1F9EA}"
      }.freeze

      def initialize(custom_emoji: {}, on_debug: nil)
        @custom_emoji = custom_emoji
        @on_debug = on_debug
        @gemoji_cache = load_gemoji_cache
      end

      def replace(text, _workspace = nil)
        result = text.dup

        # Remove skin tone modifiers (we don't render them in terminal)
        result.gsub!(SKIN_TONE_REGEX, '')

        # Replace emoji codes
        result.gsub!(EMOJI_REGEX) do
          name = ::Regexp.last_match(1)
          lookup_emoji(name) || ":#{name}:"
        end

        result
      end

      def lookup_emoji(name)
        # Check custom emoji first
        return nil if @custom_emoji[name] # Custom emoji are URLs, skip for now

        # Check gemoji cache first (from sync-standard)
        return @gemoji_cache[name] if @gemoji_cache&.key?(name)

        # Fall back to built-in map
        EMOJI_MAP[name]
      end

      def with_custom_emoji(emoji_hash)
        self.class.new(custom_emoji: emoji_hash, on_debug: @on_debug)
      end

      private

      def load_gemoji_cache
        cache_path = gemoji_cache_path
        return nil unless File.exist?(cache_path)

        JSON.parse(File.read(cache_path))
      rescue JSON::ParserError => e
        @on_debug&.call("Failed to load gemoji cache: #{e.message}")
        nil
      rescue Errno::ENOENT
        nil
      end

      def gemoji_cache_path
        File.join(ENV.fetch('XDG_CACHE_HOME', File.expand_path('~/.cache')), 'slk', 'gemoji.json')
      end
    end
  end
end
