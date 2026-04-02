# frozen_string_literal: true

require 'open3'
require 'tempfile'

class SpeakingAudioAttachmentNormalizerService
  Result = Struct.new(:tempfile, :filename, :content_type, keyword_init: true) do
    def close!
      tempfile.close!
    rescue StandardError
      tempfile.close if tempfile.respond_to?(:close)
    end
  end

  DEFAULT_FFMPEG_PATH = 'ffmpeg'

  def self.normalize_uploaded_file(uploaded_file)
    return nil if uploaded_file.blank?

    tempfile = uploaded_file.respond_to?(:tempfile) ? uploaded_file.tempfile : nil
    tempfile.rewind if tempfile.respond_to?(:rewind)

    io_data =
      if tempfile.respond_to?(:read)
        tempfile.read
      elsif uploaded_file.respond_to?(:read)
        uploaded_file.read
      end

    tempfile.rewind if tempfile.respond_to?(:rewind)
    return nil if io_data.blank?

    new(io_data:, original_filename: extract_original_filename(uploaded_file)).normalize
  end

  def self.normalize_blob(blob)
    return nil if blob.blank?

    new(
      io_data: blob.download,
      original_filename: blob.filename.to_s
    ).normalize
  end

  def self.normalize_path(path, original_filename: File.basename(path))
    new(io_data: File.binread(path), original_filename:).normalize
  end

  def self.extract_original_filename(uploaded_file)
    return uploaded_file.original_filename if uploaded_file.respond_to?(:original_filename) && uploaded_file.original_filename.present?
    return uploaded_file.path if uploaded_file.respond_to?(:path) && uploaded_file.path.present?

    'recording'
  end

  def initialize(io_data:, original_filename:)
    @io_data = io_data
    @original_filename = original_filename.to_s.strip.empty? ? 'recording' : original_filename
  end

  def normalize
    input_tempfile = build_input_tempfile
    output_tempfile = Tempfile.new([output_basename, '.mp3'], binmode: true)
    output_tempfile.close

    command = [
      ffmpeg_path,
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-i',
      input_tempfile.path,
      '-vn',
      '-acodec',
      'libmp3lame',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-b:a',
      '128k',
      output_tempfile.path
    ]

    _stdout, stderr, status = Open3.capture3(*command)

    unless status.success?
      output_tempfile.close!
      error_message = stderr.to_s.strip
      error_message = 'Unknown ffmpeg error.' if error_message.empty?
      raise "ffmpeg failed while normalizing speaking essay audio. #{error_message}"
    end

    output_tempfile.open
    output_tempfile.binmode

    Result.new(
      tempfile: output_tempfile,
      filename: output_filename,
      content_type: 'audio/mp3'
    )
  ensure
    input_tempfile&.close!
  end

  private

  attr_reader :io_data, :original_filename

  def build_input_tempfile
    tempfile = Tempfile.new([output_basename, input_extension], binmode: true)
    tempfile.write(io_data)
    tempfile.flush
    tempfile.rewind
    tempfile
  end

  def ffmpeg_path
    configured_path = ENV['FFMPEG_PATH'].to_s.strip
    configured_path.empty? ? DEFAULT_FFMPEG_PATH : configured_path
  end

  def output_basename
    sanitized = File.basename(original_filename.to_s, '.*').strip
    sanitized.empty? ? 'speaking-essay-audio' : sanitized
  end

  def output_filename
    "#{output_basename}.mp3"
  end

  def input_extension
    extension = File.extname(original_filename.to_s).downcase
    extension.empty? ? '.bin' : extension
  end
end
