class Api::V1::StorageController < ApiController
  # Upload file to storage
  def upload
    # Get the files from the request form-data
    files = params[:document]
    puts "files: #{files}"
    res = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/upload", :document => params[:document]
    render json: { success: true, message: JSON.parse(res) }, status: :ok
  end
end
