# frozen_string_literal: true

module Api
  module V1
    class FunctionsController < ApplicationController
      def index
        @functions = Function.all
        render json: { success: true, functions: @functions }, status: :ok
      end

      def show
        @function = Function.find(params[:id])
        render json: { success: true, function: @function }, status: :ok
      end

      def create
        @function = Function.new(function_params)
        if @function.save
          render json: { success: true, function: @function }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @function = Function.find(params[:id])
        if @function.update(function_params)
          render json: { success: true, function: @function }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def function_params
        params.require(:function).permit(:name, :title, :description)
      end
    end
  end
end
