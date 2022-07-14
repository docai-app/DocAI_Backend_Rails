class AzureService
  @account_name = ENV["AZURE_STORAGE_NAME"]
  @account_key = ENV["AZURE_STORAGE_ACCESS_KEY"]
  @container_name = ENV["AZURE_STORAGE_CONTAINER"]
  
  def self.upload(file)
    blob_client = Azure::Storage::Blob::BlobService.create(
      storage_account_name: @account_name,
      storage_access_key: @account_key
    )

    blob_data = File.open(file.tempfile, "rb")

    blob_name = SecureRandom.uuid + "_" + file.original_filename
    blob_name.downcase!

    blob_client.create_block_blob(@container_name, blob_name, blob_data, content_type: file.content_type)
    blob_client.get_blob_properties(@container_name, blob_name)
    
    return "https://#{@account_name}.blob.core.windows.net/#{@container_name}/#{blob_name}"
  end
end