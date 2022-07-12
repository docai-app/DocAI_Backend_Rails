class Api::V1::StorageController < ApiController
  before_action :authenticate_user!
  # Upload file to storage
  def upload
    files = params[:document]
    # try catch to upload the files
    begin
      files.each do |file|
        @document = Document.new(name: file.original_filename, file: file)
        @document.storage_url = @document.file.url.to_str
        sleep 0.5
        res = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { document_url: @document.storage_url }
        @document.content = JSON.parse(res)["result"]
        @document.save
      end
      render json: { success: true }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  def document_params
    params.require(:document).permit(:name, :storage_url, :content, :status, :file)
  end
end
