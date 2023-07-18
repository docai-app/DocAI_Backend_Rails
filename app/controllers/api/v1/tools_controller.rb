class Api::V1::ToolsController < ApplicationController
  def upload_directly_ocr
    file = params[:file]
    begin
      @file_url = AzureService.upload(file) if file.present?
      ocr_res = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/alpha/ocr", document_url: @file_url)
      content = JSON.parse(ocr_res)['result']
      render json: { success: true, file_url: @file_url, content: }, status: :ok
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end
end
