class Api::V1::OpenAiController < ApiController
  def query
    document = Document.find(params[:document_id])
    res = OpenAiService.chatWithDocument(params[:query], document.content, params[:response_format], params[:language], params[:topic], params[:style])
    render json: { success: true, response: res }, status: :ok
  end
end
