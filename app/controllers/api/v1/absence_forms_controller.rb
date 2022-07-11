class Api::V1::AbsenceFormsController < ApiController
    before_action :authenticate_user!

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
end
