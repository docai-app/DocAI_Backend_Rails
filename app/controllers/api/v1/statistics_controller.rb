class Api::V1::StatisticsController < ApplicationController
    # Count each tags by date
    def count_each_tags_by_date
        @tags = ActsAsTaggableOn::Tag.all
        @tag_count_array = []
        @tags.each do |tag|
            @tag_count = ActsAsTaggableOn::Tagging.where(tag_id: tag.id).by_day(params[:date]).count
            @tag_count_array << { tag: tag.name, count: @tag_count }
        end
        render json: { success: true, tag_count_array: @tag_count_array }, status: :ok
    end

    # Count document by date
    def count_document_by_date
        @count = Document.by_day(params[:date]).count()
        render json: { success: true, documents_count: @count }, status: :ok
    end
end
