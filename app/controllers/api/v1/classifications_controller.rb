# frozen_string_literal: true

module Api
  module V1
    class ClassificationsController < ApiController
      before_action :authenticate_user!

      # Predict the Document
      def predict
        @document = Document.find(params[:id])
        res = RestClient.get "#{ENV['DOCAI_ALPHA_URL']}/classification/predict?content=#{URI.encode_www_form_component(@document.last.content.to_s)}&model=#{getSubdomain}"
        render json: { success: true, prediction: { tag: JSON.parse(res)['label'], document: @document } }, status: :ok
      end

      # Confirm the Document
      def confirm
        @document = Document.find(params[:document_id])
        @document.label_ids = params[:tag_id]
        @document.status = :confirmed
        TagFunctionMappingService.mappping(@document.id, params[:tag_id])
        puts "Subdomain: #{getSubdomain}"
        DocumentClassificationJob.perform_async(@document.id, params[:tag_id], getSubdomain)
        if @document.save
          render json: { success: true, document: @document }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      # Update the Document Classification
      def update_classification
        document_ids = params[:document_ids]
        tag_id = params[:tag_id]

        Document.transaction do
          @documents = Document.where(id: document_ids).each do |document|
            document.update!(label_ids: tag_id, status: :confirmed, is_classified: true)
            TagFunctionMappingService.mappping(document.id, tag_id)
            DocumentClassificationJob.perform_async(document.id, tag_id, getSubdomain)
          end
        end

        render json: { success: true, documents: @documents }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      private

      def getSubdomain
        Utils.extractRequestTenantByToken(request)
      end
    end
  end
end
