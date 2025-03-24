# frozen_string_literal: true

class VocabCsvParserService
  require 'csv'

  Result = Struct.new(:success?, :vocabs, :error)

  def initialize(file)
    @file = file
  end

  def parse
    validate_file_presence
    validate_file_format

    vocabs = process_csv
    Result.new(true, vocabs, nil)
  rescue StandardError => e
    Result.new(false, nil, e.message)
  end

  private

  def validate_file_presence
    raise 'CSV file is required' unless @file.present?
  end

  def validate_file_format
    raise 'Invalid file format' unless @file.content_type == 'text/csv'
  end

  def process_csv
    csv_data = CSV.parse(@file.read, headers: true)

    raise 'CSV file is empty' if csv_data.empty?

    validate_headers(csv_data.headers)

    csv_data.map do |row|
      {
        word: row['word']&.strip,
        pos: row['pos']&.strip,
        definition: row['definition']&.strip
      }
    end
  end

  def validate_headers(headers)
    required_headers = %w[word pos definition]
    missing_headers = required_headers - headers

    return unless missing_headers.any?

    raise "Missing required columns: #{missing_headers.join(', ')}"
  end
end
