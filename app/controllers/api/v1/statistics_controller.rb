class Api::V1::StatisticsController < ApiController
  # Count each tags by date
  def count_each_tags_by_date
    @tags = ActsAsTaggableOn::Tag.all
    @tag_count_array = []
    @tags.each do |tag|
      @tag_count = ActsAsTaggableOn::Tagging.where(tag_id: tag.id).by_day(params[:date]).count
      # If tag count is 0, then skip it
      if @tag_count == 0
        next
      else
        @tag_count_array << { tag: tag.name, count: @tag_count }
      end
    end
    render json: { success: true, tags_count: @tag_count_array }, status: :ok
  end

  # Count document by date
  def count_document_by_date
    @count = Document.includes([:taggings]).by_day(params[:date]).count()
    @confirmed_count = Document.includes([:taggings]).where(status: :confirmed).where("updated_at >= ?", params[:date]).count()
    @unconfirmed_count = Document.includes([:taggings]).where.not(status: :confirmed).count()
    render json: { success: true, documents_count: @count, confirmed_count: @confirmed_count, unconfirmed_count: @unconfirmed_count }, status: :ok
  end

  # Count document status by date
  def count_document_status_by_date
    @data = Document.includes([:taggings]).find_by_sql("SELECT DATE(created_at) AS date, COUNT(*) AS uploaded_count, SUM(CASE WHEN status = '5' THEN 1 ELSE 0 END) AS ready_count, SUM(CASE WHEN status = '2' THEN 1 ELSE 0 END) AS confirmed_count, SUM(CASE WHEN status = '1' THEN 1 ELSE 0 END) AS non_ready_count FROM documents GROUP BY DATE(created_at) ORDER BY DATE(created_at) DESC")
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
      total_count: object.total_count,
    }
  end
end
