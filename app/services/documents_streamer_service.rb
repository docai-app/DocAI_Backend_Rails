# frozen_string_literal: true

# app/services/documents_streamer_service.rb
require 'erb'
require 'open-uri'
require 'addressable'

class DocumentsStreamerService
  include Enumerable

  attr_reader :documents, :folders

  def initialize(stream)
    @stream = stream
  end

  def self.stream(documents: [], folders: [], &chunks)
    new(documents:, folders:).each(documents:, folders:, &chunks)
  end

  def each(documents: [], folders: [], &block)
    writer = ZipTricks::BlockWrite.new(&block)

    ZipTricks::Streamer.open(writer) do |zip|
      add_documents_to_zip(zip, documents)
      add_folders_to_zip(zip, folders)
    end
  end

  private

  def add_documents_to_zip(zip, documents)
    documents.each do |document|
      sanitized_url = Addressable::URI.parse(document.storage_url).normalize.to_s
      add_file_to_zip(zip, sanitized_url, document.name)
    rescue StandardError => e
      Rails.logger.error "Error adding file to zip: #{e.message}"
    end
  end

  def add_folders_to_zip(zip, folders, folder_path = '')
    folders.each do |folder|
      new_folder_path = "#{folder_path}#{folder.name}/"

      # Adding the documents in the current folder to the zip
      folder.documents.each do |doc|
        sanitized_url = Addressable::URI.parse(doc.storage_url).normalize.to_s
        path = "#{new_folder_path}#{doc.name}"
        add_file_to_zip(zip, sanitized_url, path)
      rescue StandardError => e
        Rails.logger.error "Error adding file to zip: #{e.message}"
      end

      # Recursive call for the subfolders of the current folder
      add_folders_to_zip(zip, folder.folders, new_folder_path)
    end
  end

  def add_file_to_zip(zip, file_url, zip_path = '')
    URI.parse(file_url).open do |file|
      zip.write_deflated_file(zip_path) do |writer|
        IO.copy_stream(file, writer)
      end
    end
  rescue StandardError => e
    Rails.logger.error "Error adding file to zip: #{e.message}"
  end
end
