# frozen_string_literal: true

require 'zip_tricks'
require 'open-uri'

module Api
  module V1
    class DocumentsController < ApiController
      include ActionController::Live # Ensure this line is there

      before_action :set_document, only: %i[show update destroy approval]
      before_action :current_user_documents, only: %i[show_latest_predict show_specify_date_latest_predict]
      before_action :authenticate_user!, only: %i[approval download_zip]
      before_action :checkDocumentItemsIsDocument, only: [:deep_understanding]
      # before_action :require_admin, only: []

      def index
        @documents = Document.all
      end

      # Show document by id
      def show
        @document = Document.includes(:user, :labels).find(params[:id]).as_json(
          include: { user: { only: %i[id email nickname] }, labels: { only: %i[id name] } }
        )
        render json: { success: true, document: @document }, status: :ok
      end

      # Show documents by ids
      def show_by_ids
        puts params[:ids]
        @documents = Document.find(params[:ids]).as_json(except: [:label_list])
        render json: { success: true, documents: @documents }, status: :ok
      end

      # Show documents by name like name param
      def show_by_name
        @document = Document.where('name like ?',
                                   "%#{params[:name]}%").order(created_at: :desc).as_json(except: [:label_list])
        render json: { success: true, documents: @document }, status: :ok
      end

      # Show documents by content like content param
      def show_by_content
        @document = Document.includes([:taggings]).where('content like ?',
                                                         "%#{params[:content]}%").order(created_at: :desc).page params[:page]
        render json: { success: true, documents: @document, meta: pagination_meta(@document) }, status: :ok
      end

      # Show documents by ActsAsTaggableOn tag id
      def show_by_tag
        tag = ActsAsTaggableOn::Tag.find(params[:tag_id])
        @document = Document.tagged_with(tag).order(created_at: :desc).as_json(except: [:label_list])
        render json: { success: true, documents: @document }, status: :ok
      end

      # Show documents by date
      def show_by_date
        @document = Document.includes([:taggings]).where('created_at >= ?',
                                                         params[:date]).order(created_at: :desc).page params[:page]
        render json: { success: true, documents: @document, meta: pagination_meta(@document) }, status: :ok
      end

      def show_by_tag_and_content
        tag = ActsAsTaggableOn::Tag.find(params[:tag_id])
        content = params[:content] || ''
        folder_ids = Array(params[:folder_ids])
        from = params[:from] == '' ? '1970-01-01' : params[:from]
        to = params[:to] == '' ? Date.today + 1 : params[:to]

        puts "from: #{from}, to: #{to}"

        documents = Document.includes(:taggings)
                            .tagged_with(tag)
                            .where('content LIKE ?', "%#{content}%")
                            .where('documents.created_at >= ?', from.to_date)
                            .where('documents.created_at <= ?', to.to_date)
                            .order(created_at: :desc)
                            .page(params[:page])

        documents = documents.where('documents.folder_id IN (?)', folder_ids) unless folder_ids.empty?

        render json: { success: true, documents:, meta: pagination_meta(documents) }, status: :ok
      end

      # Show and Predict the Latest Uploaded Document
      def show_latest_predict
        @document = @current_user_documents.where(status: :ready).order(:created_at).page(params[:page]).per(1)
        if @document.present?
          res = RestClient.get "#{ENV['DOCAI_ALPHA_URL']}/classification/predict?content=#{URI.encode_www_form_component(@document.last.content.to_s)}&model=#{getSubdomain}"
          @tag = Tag.find(JSON.parse(res)['label']['id']).as_json(include: :functions)
          render json: { success: true, prediction: { tag: @tag, document: @document.last }, meta: pagination_meta(@document) },
                 status: :ok
        else
          render json: { success: false, error: 'No document found' }, status: :ok
        end
      end

      # Show and Predict the Specify Date Latest Uploaded Document
      def show_specify_date_latest_predict
        @document = @current_user_documents.where(status: :ready).where('created_at >= ?', params[:date].to_date).where(
          'created_at <= ?', params[:date].to_date + 1.day
        ).order(:created_at).page(params[:page]).per(1)
        @unconfirmed_count = @current_user_documents.where.not(status: :confirmed).where('created_at >= ?', params[:date].to_date).where(
          'created_at <= ?', params[:date].to_date + 1.day
        ).order(:created_at).count
        @confirmed_count = @current_user_documents.where(status: :confirmed).where('created_at >= ?', params[:date].to_date).where(
          'created_at <= ?', params[:date].to_date + 1.day
        ).order(:created_at).count
        if @document.present?
          res = RestClient.get "#{ENV['DOCAI_ALPHA_URL']}/classification/predict?content=#{URI.encode_www_form_component(@document.last.content.to_s)}&model=#{getSubdomain}"
          @tag = Tag.find(JSON.parse(res)['label_id']).as_json(include: :functions)
          render json: { success: true, prediction: { tag: @tag, document: @document.last }, confirmed_count: @confirmed_count, unconfirmed_count: @unconfirmed_count, meta: pagination_meta(@document) },
                 status: :ok
        else
          render json: { success: false, error: 'No document found' }, status: :ok
        end
      end

      # Show the PDF document details which involved each page summary and keywords
      def show_pdf_page_details
        # @document = Document.find(params[:id]).includes([:pdf_page_details]).as_json(except: [:label_list])
        @document = Document.find(params[:id]).as_json(include: { pdf_page_details: { only: %i[page_number summary
                                                                                               keywords] } })
        render json: { success: true, document: @document }, status: :ok
      end

      def pdf_search_keyword
        @document = Document.find(params[:id])
        if @document.present?
          results = VectorDbPgEmbedding.find_document_sentences_containing(params[:query], getSubdomain, @document.id)
          render json: { success: true, document: @document, results: }, status: :ok
        else
          render json: { success: false, error: 'Document not found' }, status: :not_found
        end
      end

      def create
        @document = Document.new(document_params)
        file = params['document']['file']
        @document.storage_url = AzureService.upload(file) if file.present?
        if @document.save
          render :show
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @document = Document.find(params[:id])
        if @document.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @document = Document.find(params[:id])
        if @document.update(document_params)
          render json: { success: true, document: @document }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def approval
        # binding.pry
        @document.approval_user = current_user
        @document.approval_at = DateTime.current
        @document.approval_status = params['status']
        if @document.save
          render :show
        else
          json_fail('Document approval failed')
        end
      end

      def tags
        @tags = Documents.all_tags
        render json: @tags
      end

      def ocr
        @document = Document.first
        OcrJob.perform_async(@document.id, getSubdomain)
        json_success('OCR job is queued')
      end

      def deep_understanding
        document_items = params[:document_items] || []
        needs_approval = params[:needs_approval] || false

        document_items.each do |document_item|
          @document = Document.find(document_item)
          if @document.meta.blank?
            @document.meta = {
              needs_deep_understanding: true,
              needs_approval:,
              is_deep_understanding: false,
              is_approved: false,
              form_schema_id: params[:form_schema_id]
            }
          else
            @document.meta['needs_deep_understanding'] = true
            @document.meta['needs_approval'] = needs_approval
            @document.meta['is_deep_understanding'] = false
            @document.meta['is_approved'] = false
            @document.meta['form_schema_id'] = params[:form_schema_id]
          end
          @document.save
          puts @document.inspect
        end

        render json: { success: true }, status: :ok
      end

      def qa
        @document = Document.find(params[:id])
        if @document.present?
          @metadata = {
            document_id: [@document.id]
          }
          @qaRes = AiService.assistantQA(params[:query], params[:chat_history], getSubdomain, @metadata)
          puts @qaRes
          render json: { success: true, message: @qaRes }, status: :ok
        else
          render json: { success: false, error: 'Document not found' }, status: :not_found
        end
      end

      private

      def set_document
        @document = Document.find(params[:id])
      end

      def document_params
        params.require(:document).permit(:name, :storage_url, :content, :status, :folder_id)
      end

      def document_search_params
        params.permit(:content, :tag_id, :from, :to)
      end

      def current_user_documents
        @current_user_documents = Document.where(user_id: current_user.id).or(Document.where(user_id: nil))
      end

      def pagination_meta(object)
        {
          current_page: object.current_page,
          next_page: object.next_page,
          prev_page: object.prev_page,
          total_pages: object.total_pages,
          total_count: object.total_count
        }
      end

      def getSubdomain
        Utils.extractRequestTenantByToken(request)
      end

      def checkDocumentItemsIsDocument
        document_items = params[:document_items] || []
        document_items.each do |document_item|
          @document = Document.find(document_item)
          next if @document.present? && @document.is_document?

          render json: { success: false, error: "Document #{document_item} is not a document" },
                 status: :unprocessable_entity
        end
      end
    end
  end
end
