# frozen_string_literal: true

module Api
  module V1
    class FormProjectionController < ApiController
      def preview
        @form_schema = FormSchema.find(params[:form_schema_id])
        projectionImage = FormProjectionService.preview(@form_schema, params[:data])
        base64 = FormProjectionService.exportImage2Base64(projectionImage)
        render json: { success: true, image: base64 }, status: :ok
      end

      def confirm
        @form_schema = FormSchema.find(params[:form_schema_id])
        target_folder_id = params[:target_folder_id] || nil
        filename = params[:filename] || nil
        projectionImage = FormProjectionService.preview(@form_schema, params[:data])
        begin
          @document = Document.new(name: filename, created_at: Time.zone.now, updated_at: Time.zone.now,
                                   folder_id: target_folder_id)
          if projectionImage.present?
            @document.storage_url = AzureService.uploadBlob(projectionImage.to_blob, filename,
                                                            'image/png')
          end
          @document.user_id = current_user.id if current_user.present?
          @document.uploaded!
          @form_data = FormDatum.new(data: params[:data], form_schema_id: params[:form_schema_id],
                                     document_id: @document.id)
          @form_data.save
          @document_approval = DocumentApproval.new(document_id: @document.id, form_data_id: @form_data.id,
                                                    approval_status: 0)
          @document_approval.save
          render json: { success: true }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      private

      def projection_params
        params.require(:projection).permit(:form_schema_id, :data)
      end
    end
  end
end
