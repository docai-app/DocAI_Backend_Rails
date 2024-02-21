# frozen_string_literal: true

module Api
  module V1
    class ToolsController < ApiNoauthController
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

      def text_to_png
        content = params[:content]
        begin
          pngBlob = ImageService.html2Png(content)
          blob2Base64 = FormProjectionService.exportImage2Base64(pngBlob)
          render json: { success: true, png: blob2Base64 }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def upload_html_to_pdf
        content = params[:content]
        begin
          pdfBlob = FormProjectionService.text2Pdf(content)
          file_url = AzureService.uploadBlob(pdfBlob, 'chatting_report.pdf', 'application/pdf')
          render json: { success: true, file_url: }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def upload_html_to_png
        content = params[:content]
        begin
          uri = URI("#{ENV['EXAMHERO_URL']}/tools/html_to_png")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Accept' => 'application/json')
          request.body = {
            html_content: content
          }.to_json
          http.read_timeout = 600_000

          response = http.request(request)
          res = JSON.parse(response.body)

          if res['screenshot'].present?
            img = Base64.strict_decode64(res['screenshot'])
            screenshot = Magick::ImageList.new.from_blob(img)
            file_url = AzureService.uploadBlob(screenshot.to_blob, 'chatting_report.png', 'image/png')
            render json: { success: true, file_url: }, status: :ok
          else
            render json: { success: false, error: 'Something went wrong' }, status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
