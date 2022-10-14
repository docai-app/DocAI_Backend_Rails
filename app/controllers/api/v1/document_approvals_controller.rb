class Api::V1::DocumentApprovalsController < ApiController
    def index
        @document_approvals = DocumentApproval.all
        render json: { success: true, document_approvals: @document_approvals }, status: :ok
    end

    def show
        @document_approval = DocumentApproval.find(params[:id])
        render json: { success: true, document_approval: @document_approval }, status: :ok
    end

    def show_normal_approval
        @date = Date.tomorrow - params[:days].to_i || Date.today - 3
        @absence_forms = DocumentApproval.where(approval_status: params[:status]).where(form_data_id: nil).where("created_at >= ?", @date).includes([:document, document: :taggings]).as_json(include: [:document])
        @absence_forms = Kaminari.paginate_array(@absence_forms).page(params[:page])
        render json: { success: true, absence_forms: @absence_forms, meta: pagination_meta(@absence_forms) }, status: :ok
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
