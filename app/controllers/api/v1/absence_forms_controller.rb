class Api::V1::AbsenceFormsController < ApiController
  before_action :authenticate_user!, only: []

  # Show absence form by approval status where form_schema is absence form
  def show_by_approval_status
    @absence_forms = DocumentApproval.where(approval_status: params[:status]).where(form_data_id: FormDatum.where(form_schema_id: FormSchema.where(name: "請假表").first.id))
    render json: { success: true, absence_forms: @absence_forms }, status: :ok
  end

  # Show absence fomr by approval id
  def show_by_approval_id
    @absence_form = DocumentApproval.find(params[:id]).as_json(include: [:document, :form_data])
    render json: { success: true, absence_form: @absence_form }, status: :ok
  end

  def upload
    files = params[:document]
    # try catch to upload the files
    begin
      files.each do |file|
        @document = Document.new(name: file.original_filename, file: file)
        # Split the file url by &rsct to get the url
        @document.storage_url = @document.file.url.to_str.split("&rsct")[0]
        ocrRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { :document_url => @document.file.url.to_str.split("&rsct")[0] }
        @document.content = JSON.parse(ocrRes)["result"]
        @document.save
        recognizeRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/form/recognize/absence", { :document_url => @document.file.url.to_str.split("&rsct")[0] }
        recognizeRes = JSON.parse(recognizeRes)
        @form_data = FormDatum.new(data: recognizeRes["absence_form_data"], form_schema_id: FormSchema.where(name: "請假表").first.id, document_id: @document.id)
        puts recognizeRes["absence_form_data"]
        @form_data.save
      end
      render json: { success: true, document: @document, form_data: @form_data }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end
end
