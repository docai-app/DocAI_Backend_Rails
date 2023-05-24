# frozen_string_literal: true

module Api
  module V1
    class FormProjectionController < ApplicationController
      before_action :authenticate_user!, only: [:projection]

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
            @document.storage_url = AzureService.uploadPreviewImage(projectionImage.to_blob, filename,
                                                                    'image/png')
          end
          @document.user_id = current_user.id
          @document.uploaded!
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
