class Api::V1::ClassificationsController < ApiController
  before_action :authenticate_user!

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
    @document.status = :confirmed
    # res = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/classification/confirm", { id: params[:document_id], label: params[:tag_id] }.to_json, {content_type: :json, accept: :json}
    TagFunctionMappingService.mappping(@document.id, params[:tag_id])
    if @document.save
      render json: { success: true, document: @document }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  # Update the Document Classification
  def update_classification
    document_ids = params[:document_ids]
    tag_id = params[:tag_id]

    Document.transaction do
      @documents = Document.where(id: document_ids).each do |document|
        document.update!(label_ids: tag_id, status: :confirmed, is_classified: false)
        TagFunctionMappingService.mappping(document.id, tag_id)
      end
    end

    render json: { success: true, documents: @documents }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end
end
