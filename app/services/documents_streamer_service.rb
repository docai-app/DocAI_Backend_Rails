# frozen_string_literal: true

# app/services/documents_streamer_service.rb
require 'erb'
require 'open-uri'
require 'addressable'

class DocumentsStreamerService
  include Enumerable

  attr_reader :documents

  def initialize(documents)
    @documents = documents
  end

  def self.stream(documents, &chunks)
    new(documents).each(&chunks)
  end

  def each(&block)
    writer = ZipTricks::BlockWrite.new(&block)

    ZipTricks::Streamer.open(writer) do |zip|
      documents.each do |document|
        sanitized_url = Addressable::URI.parse(document.storage_url).normalize.to_s
        URI.parse(sanitized_url).open do |file|
          zip.write_deflated_file(document.name) do |file_writer|
            IO.copy_stream(file, file_writer)
          end
        end
      rescue StandardError => e
        Rails.logger.error "Error adding file to zip: #{e.message}"
      end
    end
  end
end
