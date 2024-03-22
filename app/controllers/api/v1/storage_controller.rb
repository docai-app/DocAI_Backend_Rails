# frozen_string_literal: true

module Api
  module V1
    class StorageController < ApiController
      include Authenticatable

      before_action :authenticate, only: [:upload]

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
        classification_model_name = ClassificationModelVersion.where(entity_name: getSubdomain).order(created_at: :desc).first&.classification_model_name
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
            res = RestClient.get "#{ENV['DOCAI_ALPHA_URL']}/classification/predict?content=#{URI.encode_www_form_component(@document.content.to_s)}&model=#{classification_model_name}"
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

      def upload_general_user_file_by_url
        content_type = params[:content_type] || 'image'
        user_marketplace_item_id = params[:user_marketplace_item_id] || nil
        title = params[:title] || nil
        file_url = params[:url] || params[:file_url]
        file_size = Utils.calculate_file_size_by_url(file_url)
        GeneralUserFile.create!(
          general_user_id: current_general_user.id,
          file_type: Utils.determine_file_type(file_url), 
          file_url:, file_size:, user_marketplace_item_id: user_marketplace_item_id, title:)
        render json: { success: true, file_url: }, status: :ok
      end

      def upload_general_user_file
        content_type = params[:content_type] || 'image'
        content = params[:content] || nil
        user_marketplace_item_id = params[:user_marketplace_item_id] || nil
        title = params[:title] || nil
        begin
          @user_marketplace_item = UserMarketplaceItem.find(user_marketplace_item_id)
          if content_type == 'pdf'
            pdfBlob = FormProjectionService.text2Pdf(content)
            file_url = AzureService.uploadBlob(pdfBlob, 'chatting_report.pdf', 'application/pdf')
            file_size = Utils.calculate_file_size_by_url(file_url)
            GeneralUserFile.create!(general_user_id: current_general_user.id,
                                    file_type: Utils.determine_file_type(file_url), file_url:, file_size:, user_marketplace_item_id: @user_marketplace_item.id, title:)
          elsif content_type == 'image'
            uri = URI("#{ENV['EXAMHERO_URL']}/tools/html_to_png")
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Accept' => 'application/json')
            request.body = {
              html_content: content
            }.to_json
            http.read_timeout = 600_000

            response = http.request(request)
            res = JSON.parse(response.body)

            if res['screenshot'].present?
              img = Base64.strict_decode64(res['screenshot'])
              screenshot = Magick::ImageList.new.from_blob(img)
              file_url = AzureService.uploadBlob(screenshot.to_blob, 'chatting_report.png', 'image/png')
              file_size = Utils.calculate_file_size_by_url(file_url)
              GeneralUserFile.create!(general_user_id: current_general_user.id,
                                      file_type: Utils.determine_file_type(file_url), file_url:, file_size:, user_marketplace_item_id: @user_marketplace_item.id, title:)
            else
              render json: { success: false, error: 'Something went wrong' }, status: :unprocessable_entity
            end
          end
          render json: { success: true, file_url: }, status: :ok
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
        SmartExtractionSchema.where(label_id:).where(has_label: true).each do |schema|
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
