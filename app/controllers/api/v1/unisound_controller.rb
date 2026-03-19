# frozen_string_literal: true

require 'rest-client'
require 'securerandom'

module Api
  module V1
    class UnisoundController < ApiController
      UNISOUND_URL = 'https://edu.hivoice.cn/eval/pcm'

      def create
        text = params[:text].to_s
        audio_file = params[:voice]

        if text.blank? || audio_file.blank?
          render json: { error: 'Missing text or audio file' }, status: :bad_request
          return
        end

        raw_data = request_unisound(text, audio_file)
        engine_result = raw_data['EngineResult']

        unless engine_result
          render json: { error: 'Invalid response format from Unisound API', details: raw_data },
                 status: :internal_server_error
          return
        end

        response_data = handle_result(engine_result)
        unless response_data
          render json: { error: 'Failed to process result data' }, status: :internal_server_error
          return
        end

        render json: response_data, status: :ok
      rescue RestClient::ExceptionWithResponse => e
        render json: {
          error: "External API error: #{e.http_code}",
          details: {
            status: e.http_code,
            status_text: e.response&.description,
            data: parse_json_safely(e.response&.body) || e.response&.body
          }
        }, status: :internal_server_error
      rescue RestClient::Exceptions::ReadTimeout, RestClient::Exceptions::OpenTimeout => e
        render json: {
          error: 'No response from external API',
          details: {
            message: e.message,
            code: e.class.name
          }
        }, status: :internal_server_error
      rescue StandardError => e
        render json: {
          error: "Request setup error: #{e.message}",
          details: {
            message: e.message,
            stack: e.backtrace
          }
        }, status: :internal_server_error
      end

      private

      def request_unisound(text, audio_file)
        payload = {
          text: text,
          mode: 'E',
          voice: File.new(audio_file.tempfile.path, 'rb')
        }

        response = RestClient::Request.execute(
          method: :post,
          url: UNISOUND_URL,
          payload: payload,
          headers: {
            :'session-id' => SecureRandom.uuid,
            appkey: unisound_appkey,
            :'Wrap-Create-Time' => 'true',
            content_type: :multipart,
            accept: :json,
            multipart: true
          },
          timeout: 60
        )

        parse_json_safely(response.body) || {}
      end

      def unisound_appkey
        ENV.fetch('UNISOUND_APPKEY',
                  'ms2scwfvhot4bhibhnz5pxs6xpdx3facnf75uxq2@1b6401f8380429fe251071c6561dd288')
      end

      def parse_json_safely(body)
        return nil if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      # keep the same output contract as the old Next.js route
      def handle_result(result)
        return nil if result.blank? || result['lines'].blank?

        first_line = result['lines'][0] || {}
        sample = first_line['sample'].to_s
        user_text = first_line['usertext'].to_s
        pronunciation = first_line['score'].to_f

        words = (first_line['words'] || []).select { |word| word['type'] == 2 }
        ipa_words = []
        start_times = []
        end_times = []
        pair_accuracy_category = []
        is_letter_correct_all_words = []

        words.each do |word|
          if word['phonetic'].present?
            ipa_words << word['phonetic']
          elsif word['subwords'].present?
            ipa_words << word['subwords'].map { |sw| sw['subtext'].to_s }.join
          else
            ipa_words << ''
          end

          start_times << (word['begin'] || 0).to_s
          end_times << (word['end'] || 0).to_s

          word_score = word['score'].to_f
          is_correct = word_score >= 8 ? '1' : '0'
          pair_accuracy_category << is_correct

          if word['subwords'].present?
            word['subwords'].each do |subword|
              grapheme = subword['grapheme'].presence || subword['subtext'].to_s
              subword_score = subword['score'].to_f
              is_letter_correct = subword_score >= 8 ? '1' : '0'
              grapheme.length.times { is_letter_correct_all_words << is_letter_correct }
            end
          else
            word_text = word['text'].to_s
            is_letter_correct = word_score >= 8 ? '1' : '0'
            word_text.length.times { is_letter_correct_all_words << is_letter_correct }
          end

          is_letter_correct_all_words << ' '
        end

        real_transcript = sample.strip
        matched_transcript = user_text.strip
        real_transcripts_ipa = ipa_words.join(' ').strip

        {
          origin_data: result,
          real_transcript: real_transcript.present? ? "#{real_transcript}." : '',
          ipa_transcript: real_transcripts_ipa.present? ? "#{real_transcripts_ipa}." : '',
          pronunciation_accuracy: format('%.2f', pronunciation),
          real_transcripts: real_transcript,
          matched_transcripts: matched_transcript.present? ? "#{matched_transcript}." : '',
          real_transcripts_ipa: real_transcripts_ipa,
          matched_transcripts_ipa: real_transcripts_ipa.present? ? "#{real_transcripts_ipa}." : '',
          pair_accuracy_category: pair_accuracy_category.join(' '),
          start_time: start_times.join(' '),
          end_time: end_times.join(' '),
          is_letter_correct_all_words: is_letter_correct_all_words.join.strip
        }
      end
    end
  end
end
