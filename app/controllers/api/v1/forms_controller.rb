class Api::V1::FormsController < ApplicationController
  before_action :authenticate_user!, only: []
  before_action :find_form_schema_by_azure_form_model_id, only: [:recognize]

  # Recognize one absence form
  def recognize
    begin
      @document = Document.find(params[:id])
      @form_schema = @find_form_schema_by_azure_form_model_id
      puts @form_schema.inspect
      recognizeRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/form/recognize", { :document_url => @document.storage_url, :model_id => @form_schema.azure_form_model_id }
      recognizeRes = JSON.parse(recognizeRes)
      @form_data = FormDatum.new(data: recognizeRes["recognized_form_data"], form_schema_id: FormSchema.where(azure_form_model_id: @form_schema.azure_form_model_id).first.id, document_id: @document.id)
      @form_data.save
      @document_approval = DocumentApproval.new(document_id: @document.id, form_data_id: @form_data.id, approval_status: 0)
      @document_approval.save
      render json: { success: true, document: @document, form_data: @form_data }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def find_form_schema_by_azure_form_model_id
    @find_form_schema_by_azure_form_model_id = FormSchema.find_by(azure_form_model_id: params[:model_id])
    if @find_form_schema_by_azure_form_model_id.nil?
      render json: { success: false, error: "Form schema not found" }, status: :unprocessable_entity
    end
  end
end
