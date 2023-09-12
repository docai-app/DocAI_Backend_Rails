# frozen_string_literal: true

module Api
  module V1
    class SmartExtractionSchemasController < ApiController
      before_action :authenticate_user!, only: %i[create update destroy]

      def index
        @smart_extraction_schemas = SmartExtractionSchema.order(created_at: :desc).page(params[:page])
        render json: { success: true, smart_extraction_schemas: @smart_extraction_schemas, meta: pagination_meta(@smart_extraction_schemas) },
               status: :ok
      end

      def show
        @smart_extraction_schema = SmartExtractionSchema.find(params[:id])
        render json: { success: true, smart_extraction_schema: @smart_extraction_schema }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'SmartExtractionSchema not found' }, status: :not_found
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        unless ActsAsTaggableOn::Tag.exists?(params[:label_id])
          return render json: { success: false, error: 'Invalid label_id' },
                        status: :unprocessable_entity
        end

        schema = SmartExtractionSchema.new(smart_extraction_schema_params)
        schema.user = current_user
        schema.data_schema = params[:data_schema]

        if schema.save
          tag = ActsAsTaggableOn::Tag.find(params[:label_id])
          documents = Document.tagged_with(tag).order(created_at: :desc).as_json(except: [:label_list])

          documents.each do |document|
            DocumentSmartExtractionDatum.create(document_id: document['id'],
                                                smart_extraction_schema_id: schema.id,
                                                data: schema.data_schema)
          end

          render json: { success: true, smart_extraction_schema: schema }, status: :ok
        else
          render json: { success: false, error: schema.errors.messages }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      def update
        @smart_extraction_schema = SmartExtractionSchema.find(params[:id])
        if @smart_extraction_schema.update(smart_extraction_schema_params)
          render json: { success: true, smart_extraction_schema: @smart_extraction_schema }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @smart_extraction_schema = SmartExtractionSchema.find(params[:id])
        if @smart_extraction_schema.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def smart_extraction_schema_params
        params.require(:smart_extraction_schema).permit(:name, :description, :label_id, :data_schema, :user_id,
                                                        schema: %i[key data_type query])
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
    end
  end
end
