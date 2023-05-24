# frozen_string_literal: true

module Api
  module V1
    class FormSchemaController < ApiController
      def index
        @form_schemas = FormSchema.all
        render json: { success: true, form_schemas: @document }, status: :ok
      end

      def show
        @form_schema = FormSchema.find(params[:id])
        render json: { success: true, form_schema: @form_schema }, status: :ok
      end

      def show_by_name
        @form_schema = FormSchema.find_by(name: params[:name])
        render json: { success: true, form_schema: @form_schema }, status: :ok
      end

      def show_ready
        @form_schema = FormSchema.where(is_ready: true)
        render json: { success: true, form_schema: @form_schema }, status: :ok
      end

      def show_can_project
        @form_schema = FormSchema.where(can_project: true)
        render json: { success: true, form_schema: @form_schema }, status: :ok
      end
    end
  end
end
