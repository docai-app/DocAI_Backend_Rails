class Api::V1::ClassificationsController < ApiController
  # Predict the Document
  def predict
    res = RestClient.get ENV["DOCAI_ALPHA_URL"] + "/classification/predict?id=" + params[:id]
    @document = Document.find(params[:id])
    render json: { success: true, prediction: { tag: JSON.parse(res)["label"], document: @document } }, status: :ok
  end

  # Confirm the Document
  def confirm
    @document = Document.find(params[:document_id])
    @document.label_ids = params[:tag_id]
    @document.status = 2
    res = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/classification/confirm", { id: params[:document_id], label: params[:tag_id] }.to_json, {content_type: :json, accept: :json}
    if @document.save
      render json: { success: true, document: @document }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end
end
