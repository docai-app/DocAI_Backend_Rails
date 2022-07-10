class Api::V1::AbsenceFormsController < ApiController
    # Show absence by approval status where form_schema is absence form
    def show_by_approval_status
        @absence_forms = DocumentApproval.where(approval_status: params[:status]).where(form_data_id: FormDatum.where(form_schema_id: FormSchema.where(name: "請假表").first.id))
        render json: { success: true, absence_forms: @absence_forms }, status: :ok
    end
end
