class Api::V1::DocumentApprovalsController < ApiController
    def index
        @document_approvals = DocumentApproval.all
        render json: { success: true, document_approvals: @document_approvals }, status: :ok
    end

    def show
        @document_approval = DocumentApproval.find(params[:id])
        render json: { success: true, document_approval: @document_approval }, status: :ok
    end

    def show_normal_documents_by_approval_status
        @date = Date.tomorrow - params[:days].to_i || Date.today - 3
        @normal_documents = DocumentApproval.where(approval_status: params[:status]).where(form_data_id: nil).where("created_at >= ?", @date).includes([:document, document: :taggings]).as_json(include: [:document])
        @normal_documents = Kaminari.paginate_array(@normal_documents).page(params[:page])
        render json: { success: true, forms: @normal_documents, meta: pagination_meta(@normal_documents) }, status: :ok
    end

    def show_forms_by_approval_status
        @date = Date.tomorrow - params[:days].to_i || Date.today - 3
        @absence_forms = DocumentApproval.where(approval_status: params[:status]).where(form_data_id: FormDatum.where(form_schema_id: params[:form_schema_id])).where("created_at >= ?", @date).includes([:document, :form_data, document: :taggings]).as_json(include: [:document, :form_data])
        @absence_forms = Kaminari.paginate_array(@absence_forms).page(params[:page])
        render json: { success: true, forms: @absence_forms, meta: pagination_meta(@absence_forms) }, status: :ok
    end

    def update
        @document_approval = DocumentApproval.find(params[:id])
        if @document_approval.update(document_approval_params)
            render json: { success: true, document_approval: @document_approval }, status: :ok
        else
            render json: { success: false }, status: :unprocessable_entity
        end
    end

    private
    def document_approval_params
        params.require(:document_approval).permit(:approval_status, :remark, :signature, :signature_image_url)
    end

    def pagination_meta(object) {
        current_page: object.current_page,
        next_page: object.next_page,
        prev_page: object.prev_page,
        total_pages: object.total_pages,
        total_count: object.total_count,
      }   end
end
