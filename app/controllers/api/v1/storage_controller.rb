class Api::V1::StorageController < ApiController
  before_action :authenticate_user!, only: []
  # Upload file to storage
  def upload
    files = params[:document]
    # try catch to upload the files
    begin
      files.each do |file|
        @document = Document.new(name: file.original_filename)
        @document.storage_url = AzureService.upload(file) if file.present?
        @document.uploaded!
      end
      render json: { success: true }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  def upload_bulk_tag
    files = params[:document]
    begin
      files.each do |file|
        @document = Document.new(name: file.original_filename)
        @document.storage_url = AzureService.upload(file) if file.present?
        @document.label_ids = params[:tag_id]
        @document.uploaded!
      end
      render json: { success: true }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  def upload_directly
    file = params[:file]
    begin
      @file_url = AzureService.upload(file) if file.present?
      render json: { success: true, file_url: @file_url }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end
end
