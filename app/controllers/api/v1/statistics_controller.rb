# frozen_string_literal: true

module Api
  module V1
    class StatisticsController < ApiController
      # Count each tags by date
      def count_each_tags_by_date
        @tags = ActsAsTaggableOn::Tag.all
        @tag_count_array = []
        @tags.each do |tag|
          @tag_count = ActsAsTaggableOn::Tagging.where(tag_id: tag.id).by_day(params[:date]).count
          # If tag count is 0, then skip it
          next if @tag_count.zero?

          @tag_count_array << { tag: tag.name, count: @tag_count }
        end
        render json: { success: true, tags_count: @tag_count_array }, status: :ok
      end

      # Count document by date
      def count_document_by_date
        @count = Document.includes(%i[taggings labels]).where('is_document = true').by_day(params[:date]).count
        @confirmed_count = Document.includes(%i[taggings labels]).where('is_document = true').where(status: :confirmed).where(
          'created_at >= ?', params[:date]
        ).count
        @unconfirmed_count = Document.includes(%i[taggings labels]).where('is_document = true').where.not(status: :confirmed).where(
          'created_at >= ?', params[:date]
        ).count
        @total_unconfirmed_count = Document.includes(%i[taggings
                                                        labels]).where('is_document = true').where.not(status: :confirmed).count
        render json: { success: true, documents_count: @count, confirmed_count: @confirmed_count, unconfirmed_count: @unconfirmed_count, total_unconfirmed_count: @total_unconfirmed_count },
               status: :ok
      end

      # Count document status by date
      def count_document_status_by_date
        @data = Document.includes([:taggings]).find_by_sql("SELECT DATE(created_at) AS date, COUNT(*) AS uploaded_count, SUM(CASE WHEN status = '5' THEN 1 ELSE 0 END) AS ready_count, SUM(CASE WHEN status = '2' THEN 1 ELSE 0 END) AS confirmed_count, SUM(CASE WHEN status = '1' THEN 1 ELSE 0 END) AS non_ready_count, SUM(CASE WHEN status = '1' THEN 1 ELSE 0 END) * 20 AS estimated_time FROM documents WHERE is_document = TRUE GROUP BY DATE(created_at) ORDER BY DATE(created_at) DESC")
        @data.each do |d|
          d.date.in_time_zone('Asia/Taipei')
        end
        @data = Kaminari.paginate_array(@data).page(params[:page])
        render json: { success: true, data: @data, meta: pagination_meta(@data) }, status: :ok
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
