# frozen_string_literal: true

module Api
  module Admin
    module V1
      class LearningPathTemplatesController < ApplicationController
        before_action :set_template, only: %i[show update destroy]

        def index
          templates = LearningPathTemplate.order(position: :asc, created_at: :desc)
          templates = templates.where(status: params[:status]) if params[:status].present?
          templates = templates.where(category: params[:category]) if params[:category].present?

          render json: { success: true, learning_path_templates: templates.map(&:as_admin_json) }, status: :ok
        end

        def show
          render json: { success: true, learning_path_template: @template.as_admin_json }, status: :ok
        end

        def create
          template = LearningPathTemplate.new(template_params)
          template.created_by = current_general_user if respond_to?(:current_general_user) && current_general_user
          template.save!

          render json: { success: true, learning_path_template: template.as_admin_json }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        def update
          @template.update!(template_params)
          render json: { success: true, learning_path_template: @template.as_admin_json }, status: :ok
        rescue ActiveRecord::RecordInvalid => e
          render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        def destroy
          @template.update!(status: :archived)
          render json: { success: true, learning_path_template: @template.as_admin_json }, status: :ok
        end

        private

        def set_template
          @template = LearningPathTemplate.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'LearningPathTemplate not found' }, status: :not_found
        end

        def template_params
          params.require(:learning_path_template).permit(
            :title,
            :description,
            :emoji,
            :status,
            :level,
            :locale,
            :category,
            :position,
            prompt_config: {},
            dify_config: {},
            usage_policy: {}
          )
        end
      end
    end
  end
end
