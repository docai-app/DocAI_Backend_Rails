# frozen_string_literal: true

module Api
  module V1
    class GeneratesController < ApiController
      def storybook
        uri = URI("#{ENV['DOCAI_ALPHA_URL']}/generate/storybook")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 600_000
        request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        request.body = { query: params[:query], style: params[:style] }.to_json
        response = http.request(request)

        if response.code == '200'
          file_url = upload_pdf_to_azure(response.body) if response.body.present?
          render json: { success: true, file_url: }, status: :ok
        else
          render json: { success: false, error: 'Failed to generate storybook' }, status: :bad_request
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def upload_pdf_to_azure(file_content)
        temp_file = Tempfile.new(["storybook_#{SecureRandom.uuid}", '.pdf'], binmode: true)
        temp_file.write(file_content)
        temp_file.rewind

        mock_uploaded_file = Struct.new(:tempfile, :original_filename, :content_type).new
        mock_uploaded_file.tempfile = temp_file
        mock_uploaded_file.original_filename = File.basename(temp_file.path)
        mock_uploaded_file.content_type = 'application/pdf'

        file_url = AzureService.upload(mock_uploaded_file)
        temp_file.close
        temp_file.unlink
        file_url
      end
    end
  end
end
