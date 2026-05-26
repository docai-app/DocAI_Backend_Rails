# frozen_string_literal: true

require 'json'
require 'rest-client'
require 'uri'

module SpeakingEssay
  class DeepgramTranscriber
    ENDPOINT = 'https://api.deepgram.com/v1/listen'

    def initialize(api_key: ENV['DEEPGRAM_API_KEY'])
      @api_key = api_key.to_s.strip
    end

    def call(audio_path:, content_type:)
      raise 'DEEPGRAM_API_KEY is missing.' if @api_key.blank?
      raise "Audio file not found: #{audio_path}" unless File.exist?(audio_path)

      response = RestClient::Request.execute(
        method: :post,
        url: endpoint_url,
        payload: File.binread(audio_path),
        headers: {
          'Authorization' => "Token #{@api_key}",
          'Content-Type' => content_type.presence || 'application/octet-stream',
          'Accept' => 'application/json'
        },
        open_timeout: 15,
        timeout: timeout_seconds
      )

      raw = JSON.parse(response.body)
      normalize(raw)
    rescue RestClient::ExceptionWithResponse => e
      body = e.response&.body.to_s
      raise "Deepgram transcription failed: HTTP #{e.response&.code} #{body}"
    rescue JSON::ParserError => e
      raise "Deepgram returned invalid JSON: #{e.message}"
    end

    private

    def endpoint_url
      params = {
        model: ENV.fetch('DEEPGRAM_MODEL', 'nova-3'),
        language: ENV.fetch('ASR_LANGUAGE', 'en'),
        smart_format: 'true',
        punctuate: 'true',
        utterances: 'true',
        filler_words: 'true'
      }

      "#{ENDPOINT}?#{URI.encode_www_form(params)}"
    end

    def timeout_seconds
      ENV.fetch('SPEAKING_ESSAY_SCORING_TIMEOUT_SECONDS', '180').to_i
    end

    def normalize(raw)
      alternative = raw.dig('results', 'channels', 0, 'alternatives', 0) || {}
      words = normalize_words(alternative['words'])
      segments = normalize_segments(raw.dig('results', 'utterances'), alternative, words)

      {
        provider_name: 'deepgram',
        transcript_text: alternative['transcript'].to_s.strip,
        confidence: alternative['confidence'],
        language_code: ENV.fetch('ASR_LANGUAGE', 'en'),
        words:,
        segments:,
        raw_provider_payload: raw
      }
    end

    def normalize_words(words)
      Array(words).map do |word|
        {
          word: word['word'] || word['punctuated_word'],
          token: word['punctuated_word'] || word['word'],
          start: word['start'],
          end: word['end'],
          confidence: word['confidence']
        }
      end
    end

    def normalize_segments(utterances, alternative, words)
      segments = Array(utterances).map do |utterance|
        {
          text: utterance['transcript'],
          start: utterance['start'],
          end: utterance['end'],
          confidence: utterance['confidence']
        }
      end

      return segments if segments.present?

      transcript = alternative['transcript'].to_s.strip
      return [] if transcript.blank?

      [{
        text: transcript,
        start: words.first&.dig(:start),
        end: words.last&.dig(:end),
        confidence: alternative['confidence']
      }]
    end
  end
end
