# frozen_string_literal: true

module Api
  module V1
    class GeneratesController < ApiController
      # def storybook
      #   uri = URI("#{ENV['DOCAI_ALPHA_URL']}/generate/storybook")
      #   http = Net::HTTP.new(uri.host, uri.port)
      #   http.use_ssl = uri.scheme == 'https'
      #   request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      #   request.body = { query: params[:query], style: params[:style] }.to_json
      #   http.read_timeout = 900_000

      #   puts "Query: #{params[:query]}"
      #   puts "Style: #{params[:style]}"

      #   response = http.request(request)

      #   if res['status'] == true
      #     # file_url = upload_pdf_to_azure(response.body) if response.body.present?
      #     file_url = res['file_url']
      #     render json: { success: true, file_url: }, status: :ok
      #   else
      #     render json: { success: false, error: 'Failed to generate storybook' }, status: :bad_request
      #   end
      # rescue StandardError => e
      #   render json: { success: false, error: e.message }, status: :internal_server_error
      # end

      def storybook
        begin
          response = RestClient::Request.execute(
            method: :post,
            url: "#{ENV["DOCAI_ALPHA_URL"]}/generate/storybook",
            payload: {
              query: params[:query],
              style: params[:style],
            }.to_json,
            headers: { content_type: :json, accept: :json },
            timeout: 600,
            open_timeout: 10,
          )

          res = JSON.parse(response)
          puts "Res: #{res}"

          if res["status"] == true
            file_url = res["file_url"]
            render json: { success: true, file_url: file_url }, status: :ok
          else
            render json: { success: false, error: "Failed to generate storybook" }, status: :bad_request
          end
        rescue RestClient::Exceptions::ReadTimeout => e
          render json: { success: false, error: "Server read timeout" }, status: :gateway_timeout
        rescue RestClient::Exceptions::OpenTimeout => e
          render json: { success: false, error: "Server connection timeout" }, status: :request_timeout
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end
      end

      private

      def upload_pdf_to_azure(file_content)
        temp_file = Tempfile.new(["storybook_#{SecureRandom.uuid}", ".pdf"], binmode: true)
        temp_file.write(file_content)
        temp_file.rewind

        mock_uploaded_file = Struct.new(:tempfile, :original_filename, :content_type).new
        mock_uploaded_file.tempfile = temp_file
        mock_uploaded_file.original_filename = File.basename(temp_file.path)
        mock_uploaded_file.content_type = "application/pdf"

        file_url = AzureService.upload(mock_uploaded_file)
        temp_file.close
        temp_file.unlink
        file_url
      end
    end
  end
end
