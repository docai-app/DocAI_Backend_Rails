# frozen_string_literal: true

module TalkLabSpeaking
  class ConversationPayloadBuilder
    ROLE_LABELS = {
      'student' => 'Student',
      'ai' => 'AI',
      'assistant' => 'AI'
    }.freeze

    def initialize(raw_payload)
      @raw_payload = normalize_hash(raw_payload)
    end

    def call
      payload = @raw_payload.deep_dup
      payload['turns'] = normalized_turns
      payload['student_audio_urls'] = collect_audio_urls(payload['turns'], 'student')
      payload['ai_audio_urls'] = collect_audio_urls(payload['turns'], 'ai')
      payload['transcript'] = normalized_transcript(payload['transcript'], payload['turns'])
      payload
    end

    private

    def normalized_turns
      Array(@raw_payload['turns']).filter_map.with_index do |turn, index|
        next unless turn.is_a?(Hash)

        normalized = turn.deep_stringify_keys
        role = normalized['role'].to_s.presence || 'student'
        role = 'ai' if role == 'assistant'

        {
          'turn_index' => normalized['turn_index'].presence || normalized['index'].presence || index + 1,
          'role' => role,
          'text' => normalized['text'].to_s,
          'audio_url' => normalized['audio_url'].presence,
          'started_at' => normalized['started_at'].presence,
          'ended_at' => normalized['ended_at'].presence,
          'duration_seconds' => normalized['duration_seconds'].presence
        }.compact
      end
    end

    def normalized_transcript(raw_transcript, turns)
      transcript = raw_transcript.to_s.strip
      return transcript if transcript.present?

      turns.filter_map do |turn|
        text = turn['text'].to_s.strip
        next if text.blank?

        "#{ROLE_LABELS.fetch(turn['role'].to_s, turn['role'].to_s.titleize)}: #{text}"
      end.join("\n")
    end

    def collect_audio_urls(turns, role)
      turns.filter_map do |turn|
        next unless turn['role'].to_s == role

        turn['audio_url'].presence
      end
    end

    def normalize_hash(value)
      case value
      when ActionController::Parameters
        value.to_unsafe_h.deep_stringify_keys
      when Hash
        value.deep_stringify_keys
      else
        {}
      end
    end
  end
end
