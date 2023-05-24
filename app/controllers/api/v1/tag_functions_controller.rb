# frozen_string_literal: true

module Api
  module V1
    class TagFunctionsController < ApplicationController
      before_action :authenticate_user!, only: %i[create update]

      def index
        @tag_functions = TagFunction.all
        render json: { success: true, tag_functions: @tag_functions }, status: :ok
      end

      def show
        @tag_function = TagFunction.find(params[:id])
        render json: { success: true, tag_function: @tag_function }, status: :ok
      end

      def create
        @tag_function = TagFunction.new(tag_function_params)
        if @tag_function.save
          render json: { success: true, tag_function: @tag_function }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @tag_function = TagFunction.find_by(tag_id: params[:tag_id], function_id: params[:function_id])
        puts @tag_function.inspect
        if @tag_function.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @tag_function = TagFunction.find(params[:id])
        if @tag_function.update(tag_function_params)
          render json: { success: true, tag_function: @tag_function }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def tag_function_params
        params.require(:tag_function).permit(:tag_id, :function_id)
      end
    end
  end
end
