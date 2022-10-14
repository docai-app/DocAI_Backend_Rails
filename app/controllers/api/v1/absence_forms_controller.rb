class Api::V1::AbsenceFormsController < ApiController
  before_action :authenticate_user!, only: []

  # Show absence form by approval status where form_schema is absence form
  def show_by_approval_status
    @date = Date.tomorrow - params[:days].to_i || Date.today - 3
    @absence_forms = DocumentApproval.where(approval_status: params[:status]).where(form_data_id: FormDatum.where(form_schema_id: FormSchema.where(name: "請假表").first.id)).where("created_at >= ?", @date).includes([:document, :form_data, document: :taggings]).as_json(include: [:document, :form_data])
    @absence_forms = Kaminari.paginate_array(@absence_forms).page(params[:page])
    render json: { success: true, absence_forms: @absence_forms, meta: pagination_meta(@absence_forms) }, status: :ok
  end

  # Show absence fomr by approval id
  def show_by_approval_id
    @absence_form = DocumentApproval.find(params[:id]).as_json(include: [:document, :form_data])
    render json: { success: true, absence_form: @absence_form }, status: :ok
  end

  # Update absence form by approval id
  def update
  end

  def upload
    files = params[:document]
    # try catch to upload the files
    begin
      files.each do |file|
        @document = Document.new(name: file.original_filename)
        # Split the file url by &rsct to get the url
        @document.storage_url = AzureService.upload(file) if file.present?
        ocrRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { :document_url => @document.storage_url }
        @document.content = JSON.parse(ocrRes)["result"]
        @document.save
        recognizeRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/form/recognize/absence", { :document_url => @document.storage_url }
        recognizeRes = JSON.parse(recognizeRes)
        @form_data = FormDatum.new(data: recognizeRes["absence_form_data"], form_schema_id: FormSchema.where(name: "請假表").first.id, document_id: @document.id)
        @form_data.save
        @document_approval = DocumentApproval.new(document_id: @document.id, form_data_id: @form_data.id, approval_status: 0)
        @document_approval.save
      end
      render json: { success: true, document: @document, form_data: @form_data }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  # Recognize one absence form
  def recognize_specific
    begin
      @document = Document.find(params[:id])
      recognizeRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/form/recognize/absence", { :document_url => @document.storage_url }
      recognizeRes = JSON.parse(recognizeRes)
      @form_data = FormDatum.new(data: recognizeRes["absence_form_data"], form_schema_id: FormSchema.where(name: "請假表").first.id, document_id: @document.id)
      @form_data.save
      @document_approval = DocumentApproval.new(document_id: @document.id, form_data_id: @form_data.id, approval_status: 0)
      @document_approval.save
      render json: { success: true, document: @document, form_data: @form_data }, status: :ok
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def pagination_meta(object) {
    current_page: object.current_page,
    next_page: object.next_page,
    prev_page: object.prev_page,
    total_pages: object.total_pages,
    total_count: object.total_count,
  }   end
end
