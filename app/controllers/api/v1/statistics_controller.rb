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
    @confirmed_count = Document.includes([:taggings]).by_day(params[:date]).where(status: :confirmed).count()
    @unconfirmed_count = Document.includes([:taggings]).where(status: !:confirmed).count()
    render json: { success: true, documents_count: @count, confirmed_count: @confirmed_count, unconfirmed_count: @unconfirmed_count }, status: :ok
  end

  # Count document status by date
  def count_document_status_by_date
    @uploaded_count = Document.includes([:taggings]).by_day(params[:date]).count()
    @ready_count = Document.includes([:taggings]).by_day(params[:date]).where(status: :ready).count()
    @confirmed_count = Document.includes([:taggings]).by_day(params[:date]).where(status: :confirmed).count()
    render json: { success: true, uploaded_count: @uploaded_count, confirmed_count: @confirmed_count, ready_count: @ready_count }, status: :ok
  end
end
