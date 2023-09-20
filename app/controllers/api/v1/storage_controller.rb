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
            documentProcessors(file)
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
            @document.is_classified = true
            @document.save
            documentProcessors(file)
            documentSmartExtraction(params[:tag_id])
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

      def upload_generated_content
        target_folder_id = params[:target_folder_id] || nil
        params[:filename] || SecureRandom.uuid
        content = params[:content] || nil
        begin
          @document = Document.new(name: params[:filename], content:, folder_id: target_folder_id)
          text2Pdf = FormProjectionService.text2Pdf(content)
          @document.storage_url = AzureService.uploadBlob(text2Pdf, params[:filename], 'application/pdf')
          @document.user = current_user
          @document.uploaded!
          render json: { success: true, document: @document }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def chatbot_upload
        file = params[:file]
        @chatbot = Chatbot.find(params[:chatbot_id])
        unless @chatbot.is_public == false
          return render json: { success: false, error: 'Cannot Upload File' },
                        status: :not_found
        end

        begin
          @document = Document.new(name: file.original_filename, created_at: Time.zone.now, updated_at: Time.zone.now,
                                   folder_id: params[:target_folder_id] || nil)
          @document.storage_url = AzureService.upload(file) if file.present?
          documentProcessors(file, false)
          puts @document.inspect
          if @document.content.present?
            res = RestClient.get "#{ENV['DOCAI_ALPHA_URL']}/classification/predict?content=#{URI.encode_www_form_component(@document.content.to_s)}&model=#{getSubdomain}"
            @label = Tag.find(JSON.parse(res)['label_id'])
            render json: { success: true, prediction: { label: @label, document: @document } },
                   status: :ok
          else
            render json: { success: false }, status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      private

      def documentProcessors(file, async = true)
        if DocumentService.checkFileIsDocument(file)
          @document.uploaded!
          if async
            OcrJob.perform_async(@document.id, getSubdomain)
          else
            ocr_res = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/alpha/ocr", document_url: @document.storage_url)
            content = JSON.parse(ocr_res)['result']
            @document.content = content
            @document.ready!
          end
        elsif DocumentService.checkFileIsTextDocument(file)
          @document.content = DocumentService.readTextDocument2Text(file)
          @document.meta = {
            is_text_document: true
          }
          @document.ready!
        else
          @document.is_document = false
          @document.uploaded!
        end
        puts @document.inspect
      end

      def documentSmartExtraction(label_id)
        SmartExtractionSchema.where(label_id:).each do |schema|
          DocumentSmartExtractionDatum.create(document_id: @document.id, smart_extraction_schema_id: schema.id,
                                              data: schema.data_schema)
        end
      end

      def getSubdomain
        Utils.extractRequestTenantByToken(request)
      end
    end
  end
end
