# frozen_string_literal: true

module Api
  module V1
    class AssessmentRecordsController < ApiController
      include Authenticatable

      before_action :authenticate_general_user!, only: %i[show create update destroy]

      def show_student_assessments
        
      end

      def students
        # 顯示所有管理的學生的總列表
        teacher = current_general_user
        binding.pry
        # AssessmentRecord.where
      end

      def show
        @ar = AssessmentRecord.find(params[:id])
        render json: { success: true, assessment_record: @ar }, status: :ok
      end

      def index; end

      def create
        @ar = AssessmentRecord.new
        @ar.recordable = current_general_user
        @ar.meta = params['assessment_record']['meta']
        @ar.record = params['assessment_record']['record']
        @ar.title = @ar.meta['topic']
        if @ar.save
          render json: { success: true, assessment_record: @ar }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy; end

      def assessment_record_params
        params.require(:assessment_record).permit(:id, :title, :recordable)
      end
    end
  end
end
