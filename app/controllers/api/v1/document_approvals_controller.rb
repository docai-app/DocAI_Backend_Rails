class Api::V1::DocumentApprovalsController < ApiController
    def index
        @document_approvals = DocumentApproval.all
        render json: { success: true, document_approvals: @document_approvals }, status: :ok
    end

    def show
        @document_approval = DocumentApproval.find(params[:id])
        render json: { success: true, document_approval: @document_approval }, status: :ok
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
        params.require(:document_approval).permit(:approval_status, :remark)
    end
end
