# frozen_string_literal: true

module Api
  module V1
    class TagsController < ApiController
      # Show all tags
      def index
        @tags = Tag.joins(:taggings).select('tags.*,context').where("context = 'labels'").distinct.includes(%i[
                                                                                                              functions tag_functions
                                                                                                            ]).as_json(include: :functions)
        render json: { success: true, tags: @tags }, status: :ok
      end

      # Show tag by id
      def show
        @tag = Tag.find(params[:id]).as_json(include: :functions)
        render json: { success: true, tag: @tag }, status: :ok
      end

      # Show the distinct tags which is tagged by document
      def show_by_tagging
        @tags = ActsAsTaggableOn::Tagging.distinct.pluck(:tag_id).map { |id| ActsAsTaggableOn::Tag.find(id) }
        render json: { success: true, tags: @tags }, status: :ok
      end

      # Show the functions of tag
      def show_functions
        @tag = Tag.find(params[:id]).as_json(include: :functions)
        render json: { success: true, functions: @tag['functions'] }, status: :ok
      end

      # Create tag
      def create
        @tag = ActsAsTaggableOn::Tag.new(tag_params)
        if @tag.save
          render json: { success: true, tag: @tag }, status: :ok
        else
          render json: { success: false, errors: @tag.errors }, status: :ok
        end
      end

      # Update tag
      def update
        @tag = ActsAsTaggableOn::Tag.find(params[:id])
        if @tag.update(tag_params)
          render json: { success: true, tag: @tag }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def tag_params
        params.require(:tag).permit(:name, :is_checked)
      end
    end
  end
end
