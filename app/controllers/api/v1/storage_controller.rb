# frozen_string_literal: true

module Api
  module V1
    class StorageController < ApiController
      before_action :authenticate_user!, only: [:upload]

      # Upload file to storage
      def upload
        files = params[:document]
        target_folder_id = params[:target_folder_id] || nil
        # try catch to upload the files
        begin
          files.each do |file|
            @document = Document.new(name: file.original_filename, created_at: Time.zone.now, updated_at: Time.zone.now,
                                     folder_id: target_folder_id)
            @document.storage_url = AzureService.upload(file) if file.present?
            @document.user = current_user
            if DocumentService.checkFileIsDocument(file)
              @document.uploaded!
              OcrJob.perform_async(@document.id, getSubdomain)
            else
              @document.is_document = false
              @document.uploaded!
            end
          end
          render json: { success: true }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def upload_batch_tag
        files = params[:document]
        target_folder_id = params[:target_folder_id] || nil
        needs_deep_understanding = params[:needs_deep_understanding] || false
        needs_approval = params[:needs_approval] || false
        puts "Application Tenant: #{getSubdomain}"
        begin
          files.each do |file|
            @document = Document.new(name: file.original_filename, created_at: Time.zone.now, updated_at: Time.zone.now,
                                     folder_id: target_folder_id)
            @document.meta = {
              needs_deep_understanding:,
              needs_approval:,
              is_deep_understanding: false,
              is_approved: false,
              form_schema_id: params[:form_schema_id]
            }
            @document.storage_url = AzureService.upload(file) if file.present?
            @document.user = current_user
            @document.label_ids = params[:tag_id]
            @document.save
            if DocumentService.checkFileIsDocument(file)
              @document.confirmed!
              OcrJob.perform_async(@document.id, getSubdomain)
              DocumentClassificationJob.perform_async(@document.id, params[:tag_id], getSubdomain)
              if needs_deep_understanding == 'true'
                puts "#{@document.id} needs_deep_understanding, #{params[:form_schema_id]}, #{needs_approval}"
                FormDeepUnderstandingJob.perform_async(@document.id, params[:form_schema_id], needs_approval,
                                                       getSubdomain)
              end
            else
              @document.is_document = false
              @document.uploaded!
            end
          end
          render json: { success: true }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def upload_directly
        file = params[:file]
        begin
          @file_url = AzureService.upload(file) if file.present?
          render json: { success: true, file_url: @file_url }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      private

      def getSubdomain
        Utils.extractReferrerSubdomain(request.referrer) || 'public'
      end
    end
  end
end
