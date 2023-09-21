# frozen_string_literal: true

module Api
  module V1
    class DocumentSmartExtractionDatumController < ApiController
      def index
        @document_smart_extraction_datum = DocumentSmartExtractionDatum.all.page(params[:page])
        render json: { success: true, document_smart_extraction_datum: @document_smart_extraction_datum, meta: pagination_meta(@document_smart_extraction_datum) },
               status: :ok
      end

      def show
        @document_smart_extraction_datum = DocumentSmartExtractionDatum.find(params[:id])
        render json: { success: true, document_smart_extraction_datum: @document_smart_extraction_datum }, status: :ok
      end

      def update_data
        @document_smart_extraction_datum = DocumentSmartExtractionDatum.find(params[:id])
        @smart_extraction_schema = @document_smart_extraction_datum.smart_extraction_schema
        if Utils.matchingKeys?(@smart_extraction_schema.data_schema, params[:data])
          if @document_smart_extraction_datum.update(data: params[:data])
            render json: { success: true, document_smart_extraction_datum: @document_smart_extraction_datum },
                   status: :ok
          else
            render json: { success: false }, status: :unprocessable_entity
          end
        else
          render json: { success: false, error: 'Invalid data' }, status: :unprocessable_entity
        end
      end

      def destroy
        @document_smart_extraction_datum = DocumentSmartExtractionDatum.find(params[:id])
        if @document_smart_extraction_datum.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def show_by_filter_and_smart_extraction_schema_id
        filter = params[:filter]

        query = DocumentSmartExtractionDatum.where(smart_extraction_schema_id: params[:smart_extraction_schema_id])

        filter.each do |key, value|
          query = query.where('data->>? LIKE ?', key, "%#{value}%")
        end

        @document_smart_extraction_datum = query.order(created_at: :desc)
                                                .includes(:document)
                                                .as_json(include: { document: { except: [:label_list] } })

        render json: { success: true, document_smart_extraction_datum: @document_smart_extraction_datum }, status: :ok
      end

      private

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
