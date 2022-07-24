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
        res = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { :document_url => @document.storage_url }
        @document.content = JSON.parse(res)["result"]
        @document.save
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
        res = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { :document_url => @document.storage_url }
        @document.content = JSON.parse(res)["result"]
        @document.label_ids = params[:tag_id]
        @document.status = 2
        @document.save
      end
      render json: { success: true }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  def document_params
    # params.require(:document).permit(:name, :storage_url, :content, :status, :file)
    # params.require(:document).permit(:name, :storage_url, :content, :status)
  end
end
