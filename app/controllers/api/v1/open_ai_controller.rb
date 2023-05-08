class Api::V1::OpenAiController < ApiController
  def query
    begin
      document = Document.find(params[:document_id])
      response = OpenAiService.chatWithDocument(params[:query], document.content, params[:response_format], params[:language], params[:topic], params[:style])
      render json: { success: true, response: response }, status: :ok
    rescue ActiveRecord::RecordNotFound => e
      render json: { success: false, error: e.message }, status: :not_found
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end

  def query_documents
    begin
      documents = Document.find(params[:document_ids])
      content = Utils.concatDocumentsContent(documents)
      response = OpenAiService.chatWithDocuments(params[:query], content, params[:response_format], params[:language], params[:topic], params[:style])
      render json: { success: true, response: response }, status: :ok
    rescue ActiveRecord::RecordNotFound => e
      render json: { success: false, error: e.message }, status: :not_found
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end
end
