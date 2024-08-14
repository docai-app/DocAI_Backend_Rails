# frozen_string_literal: true

require 'azure/storage/blob'

Azure::Storage::Blob::BlobService.create(
  storage_account_name: ENV['AZURE_STORAGE_NAME'],
  storage_access_key: ENV['AZURE_STORAGE_ACCESS_KEY']
)
