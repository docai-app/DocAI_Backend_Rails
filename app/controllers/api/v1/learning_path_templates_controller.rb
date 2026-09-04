# frozen_string_literal: true

module Api
  module V1
    class LearningPathTemplatesController < ApiController
      before_action :authenticate_general_user!

      def index
        templates = LearningPathTemplate.visible_to_students
        render json: { success: true, learning_path_templates: templates.map(&:as_student_json) }, status: :ok
      end

      def show
        template = LearningPathTemplate.visible_to_students.find(params[:id])
        render json: { success: true, learning_path_template: template.as_student_json }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'LearningPathTemplate not found' }, status: :not_found
      end
    end
  end
end
