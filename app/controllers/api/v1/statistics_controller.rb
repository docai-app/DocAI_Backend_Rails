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
    @confirmed_count = Document.includes([:taggings]).where(status: :confirmed).where("updated_at >= ? AND updated_at <= ?", params[:date].to_datetime.beginning_of_day, params[:date].to_datetime.end_of_day).count()
    @unconfirmed_count = Document.includes([:taggings]).where.not(status: :confirmed).count()
    render json: { success: true, documents_count: @count, confirmed_count: @confirmed_count, unconfirmed_count: @unconfirmed_count }, status: :ok
  end

  # Count document status by date
  def count_document_status_by_date
    @date = params[:date].to_datetime
    @days = params[:days].to_i
    @data_array = []
    @days.times do
      @items = {}
      @items[:date] = @date.strftime("%Y-%m-%d")
      @items[:uploaded_count] = Document.by_day(@date).count()
      @items[:ready_count] = Document.by_day(@date).where(status: :ready).count()
      @items[:confirmed_count] = Document.by_day(@date).where(status: :confirmed).count()
      @items[:non_ready_count] = Document.by_day(@date).where(status: :uploaded).count()
      # estimated_time time is in minutes
      @items[:estimated_time] = @items[:non_ready_count] * 20
      @data_array << @items
      @date = @date - 1.day
    end
    render json: { success: true, data: @data_array }, status: :ok
  end
end
