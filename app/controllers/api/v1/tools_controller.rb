# frozen_string_literal: true

module Api
  module V1
    class ToolsController < ApplicationController
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

      def text_to_pdf
        content = params[:content]
        begin
          pdfBlob = FormProjectionService.text2Pdf(content)
          blob2Base64 = FormProjectionService.exportImage2Base64(pdfBlob)
          render json: { success: true, pdf: blob2Base64 }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
