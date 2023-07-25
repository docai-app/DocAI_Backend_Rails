# frozen_string_literal: true

module Api
  module V1
    class OpenAiController < ApiController
      def query
        document = Document.find(params[:document_id])
        response = OpenAiService.chatWithDocument(params[:query], document.content, params[:response_format],
                                                  params[:language], params[:topic], params[:style])
        render json: { success: true, response: }, status: :ok
      rescue ActiveRecord::RecordNotFound => e
        render json: { success: false, error: e.message }, status: :not_found
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def query_documents
        documents = Document.find(params[:document_ids])
        content = Utils.concatDocumentsContent(documents)
        response = OpenAiService.chatWithDocuments(params[:query], content, params[:response_format], params[:language],
                                                   params[:topic], params[:style])
        # response = AiService.generateContentByDocuments(params[:query], content, params[:response_format], params[:language], params[:topic], params[:style])
        render json: { success: true, response: }, status: :ok
      rescue ActiveRecord::RecordNotFound => e
        render json: { success: false, error: e.message }, status: :not_found
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end
    end
  end
end
