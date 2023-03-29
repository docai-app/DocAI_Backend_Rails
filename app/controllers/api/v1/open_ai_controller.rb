class Api::V1::OpenAiController < ApiController
  def query
    document = Document.find(params[:document_id])
    res = OpenAiService.chatWithDocument(params[:query], document.content)
    render json: { success: true, response: res }, status: :ok
  end
end
