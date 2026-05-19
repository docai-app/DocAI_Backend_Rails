# frozen_string_literal: true

require 'json'
require 'open3'
require 'tempfile'

module SpeakingEssay
  class AzurePronunciationAssessor
    # Azure Speech SDK 的 AudioConfig(filename=...) 仅支持 PCM WAV (16kHz / 16-bit / mono)。
    # 这里统一用 ffmpeg 转一次，避免 webm/m4a/mp3 或不规范 WAV 头导致 SPXERR_INVALID_HEADER。
    AZURE_AUDIO_SAMPLE_RATE = 16_000
    AZURE_AUDIO_CHANNELS = 1

    def call(audio_path:, reference_text:)
      raise 'AZURE_SPEECH_KEY is missing.' if ENV['AZURE_SPEECH_KEY'].blank?
      raise 'AZURE_SPEECH_REGION is missing.' if ENV['AZURE_SPEECH_REGION'].blank?
      raise 'Transcript is blank; Azure pronunciation assessment requires reference text.' if reference_text.blank?

      reference_file = Tempfile.new(['speaking-reference', '.txt'])
      reference_file.write(reference_text.to_s)
      reference_file.close

      with_pcm_wav(audio_path) do |pcm_wav_path|
        stdout, stderr, status = Open3.capture3(
          env,
          python_bin,
          script_path,
          '--audio',
          pcm_wav_path,
          '--reference',
          reference_file.path,
          '--locale',
          ENV.fetch('AZURE_SPEECH_LOCALE', 'en-US')
        )

        raise "Azure pronunciation failed: #{stderr.presence || stdout}" unless status.success?

        return normalize(JSON.parse(stdout))
      end
    rescue JSON::ParserError => e
      raise "Azure pronunciation returned invalid JSON: #{e.message}"
    ensure
      reference_file&.close
      reference_file&.unlink
    end

    private

    def env
      {
        'AZURE_SPEECH_KEY' => ENV.fetch('AZURE_SPEECH_KEY'),
        'AZURE_SPEECH_REGION' => ENV.fetch('AZURE_SPEECH_REGION'),
        'AZURE_SPEECH_LOCALE' => ENV.fetch('AZURE_SPEECH_LOCALE', 'en-US')
      }
    end

    def python_bin
      ENV.fetch('AZURE_SPEECH_PYTHON_BIN', 'python3')
    end

    def script_path
      Rails.root.join('script', 'azure_pronunciation_continuous.py').to_s
    end

    def ffmpeg_bin
      ENV.fetch('FFMPEG_BIN', 'ffmpeg')
    end

    def with_pcm_wav(source_path)
      wav_file = Tempfile.new(['speaking-azure', '.wav'], binmode: true)
      wav_file.close

      # 限制 ffmpeg 单线程，避免 sidekiq 多并发时它自身又开多线程抢核
      # 音频转码本质是 IO + 简单 DSP，单线程足够，120s 录音通常 < 2s 完成
      _stdout, stderr, status = Open3.capture3(
        ffmpeg_bin,
        '-y',
        '-nostdin',
        '-loglevel', 'error',
        '-threads', '1',
        '-i', source_path.to_s,
        '-ac', AZURE_AUDIO_CHANNELS.to_s,
        '-ar', AZURE_AUDIO_SAMPLE_RATE.to_s,
        '-acodec', 'pcm_s16le',
        '-f', 'wav',
        wav_file.path
      )

      unless status.success?
        raise "Azure pronunciation failed: ffmpeg transcode error: #{stderr.to_s.strip}"
      end

      yield wav_file.path
    rescue Errno::ENOENT => e
      raise "Azure pronunciation failed: ffmpeg is not available (#{e.message}). " \
            'Install ffmpeg in the runtime image or set FFMPEG_BIN.'
    ensure
      wav_file&.close
      wav_file&.unlink
    end

    def normalize(raw)
      assessment = raw.dig('aggregated_result', 'PronunciationAssessment') || {}
      words = raw.dig('aggregated_result', 'NBest', 0, 'Words') || []

      {
        provider_name: 'azure_speech',
        overall_score: band_from_hundred(assessment['PronScore']),
        raw_pronunciation_score: assessment['PronScore'],
        accuracy_score: assessment['AccuracyScore'],
        fluency_score: assessment['FluencyScore'],
        prosody_score: assessment['ProsodyScore'],
        completeness_score: assessment['CompletenessScore'],
        word_level_feedback: words.map do |word|
          word_assessment = word['PronunciationAssessment'] || {}
          raw_score = word_assessment['AccuracyScore']

          {
            word: word['Word'] || word['DisplayText'],
            raw_score:,
            score: band_from_hundred(raw_score),
            issue: word_assessment['ErrorType'].presence || 'None'
          }
        end,
        raw_provider_payload: raw
      }
    end

    def band_from_hundred(score)
      return nil if score.nil?

      band = (score.to_f / 100.0 * 9.0 * 2).round / 2.0
      [[band, 0].max, 9].min
    end
  end
end
