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

      def show_by_filter_and_smart_extraction_schema_id
        @document_smart_extraction_datum = DocumentSmartExtractionDatum.where(smart_extraction_schema_id: params[:smart_extraction_schema_id]).where(
          'data @> ?', params[:filter].to_json
        ).order(created_at: :desc).includes(%i[
                                              document
                                            ]).as_json(include: {
                                                         document: { except: [:label_list] }
                                                       })
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
