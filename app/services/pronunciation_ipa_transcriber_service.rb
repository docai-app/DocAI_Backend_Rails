# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'

class PronunciationIpaTranscriberService
  REMOTE_API_URL = 'https://pronunciation.m2mda.com/pinyin'
  DEFAULT_VOICE = 'en-us'
  ZERO_WIDTH_JOINER = "\u200D"

  def enrich_sentences(sentences)
    Array(sentences).map { |sentence_obj| enrich_sentence(sentence_obj) }
  end

  def enrich_sentence(sentence_obj)
    return sentence_obj unless sentence_obj.is_a?(Hash)

    sentence = sentence_obj['sentence'] || sentence_obj[:sentence]
    return sentence_obj if sentence.blank?

    ipa_transcript = transcribe(sentence.to_s)
    return sentence_obj if ipa_transcript.blank?

    sentence_obj.merge('ipa_transcript' => ipa_transcript)
  end

  def transcribe(sentence)
    normalized_sentence = sentence.to_s.strip
    return if normalized_sentence.blank?

    normalize_ipa(
      transcribe_with_espeak_phonemizer(normalized_sentence) ||
      transcribe_with_espeak_ng(normalized_sentence) ||
      transcribe_with_remote_service(normalized_sentence)
    )
  end

  def transcribe_with_espeak_phonemizer(sentence)
    return unless linux_platform?

    command = resolve_command(espeak_phonemizer_candidates)
    return unless command

    stdout, stderr, status = Open3.capture3({}, command, '-v', voice, stdin_data: sentence)
    return stdout if status.success?

    Rails.logger.warn("espeak-phonemizer failed: #{stderr.presence || stdout}")
    nil
  rescue StandardError => e
    Rails.logger.error("espeak-phonemizer error: #{e.class} #{e.message}")
    nil
  end

  def transcribe_with_espeak_ng(sentence)
    command = resolve_command(espeak_ng_candidates)
    return unless command

    env = {}
    env['ESPEAK_DATA_PATH'] = espeak_data_path if espeak_data_path.present?

    stdout, stderr, status = Open3.capture3(
      env,
      command,
      '-q',
      '--ipa=3',
      '-v',
      voice,
      sentence
    )
    return stdout if status.success?

    Rails.logger.warn("espeak-ng failed: #{stderr.presence || stdout}")
    nil
  rescue StandardError => e
    Rails.logger.error("espeak-ng error: #{e.class} #{e.message}")
    nil
  end

  def transcribe_with_remote_service(sentence)
    uri = URI(REMOTE_API_URL)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = { language: 'en', sentence: sentence }.to_json

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 10
    http.open_timeout = 5

    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ca_file = ENV['SSL_CERT_FILE'].presence || '/etc/ssl/cert.pem'
      http.ca_file = ca_file if File.exist?(ca_file)
    end

    response = http.request(request)
    return unless response.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(response.body)
    parsed['ipa_transcript'] || parsed['ipa'] || parsed.dig('data', 'ipa_transcript')
  rescue JSON::ParserError => e
    Rails.logger.error("Pronunciation fallback parse error: #{e.class} #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.error("Pronunciation fallback error: #{e.class} #{e.message}")
    nil
  end

  def voice
    ENV['ESPEAK_IPA_VOICE'].presence || DEFAULT_VOICE
  end

  def espeak_phonemizer_candidates
    [
      ENV['ESPEAK_PHONEMIZER_BIN'].presence,
      File.expand_path('~/Library/Python/3.9/bin/espeak-phonemizer'),
      'espeak-phonemizer'
    ].compact
  end

  def espeak_ng_candidates
    [
      ENV['ESPEAK_NG_BIN'].presence,
      File.expand_path('~/.local/espeak-ng/bin/espeak-ng'),
      'espeak-ng',
      'espeak'
    ].compact
  end

  def espeak_data_path
    env_path = ENV['ESPEAK_DATA_PATH'].presence
    return env_path if env_path.present?

    default_path = File.expand_path('~/.local/espeak-ng/share/espeak-ng-data')
    File.directory?(default_path) ? default_path : nil
  end

  def resolve_command(candidates)
    Array(candidates).each do |candidate|
      next if candidate.blank?

      if path_like?(candidate)
        expanded = File.expand_path(candidate)
        return expanded if File.executable?(expanded)
      elsif command_on_path?(candidate)
        return candidate
      end
    end

    nil
  end

  def normalize_ipa(raw_ipa)
    return if raw_ipa.blank?

    raw_ipa
      .to_s
      .encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      .delete(ZERO_WIDTH_JOINER)
      .gsub(/\s+/, ' ')
      .strip
      .presence
  end

  def linux_platform?
    RUBY_PLATFORM.include?('linux')
  end

  private

  def path_like?(candidate)
    candidate.include?(File::SEPARATOR) || candidate.start_with?('.')
  end

  def command_on_path?(command)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |directory|
      executable = File.join(directory, command)
      File.executable?(executable) && !File.directory?(executable)
    end
  end
end
