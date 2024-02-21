module Api
  module V1
    class AssessmentRecordsController < ApiController
      include Authenticatable

      before_action :authenticate, only: %i[show create update destroy]

      def show
        @ar = AssessmentRecord.find(params[:id])
        render json: { success: true, assessment_record: @ar}, status: :ok
      end
      
      def index
      end

      def create
        @ar = AssessmentRecord.new(ar_params)
        @ar.user = current_user
        if @ar.save
          render json: { success: true, assessment_record: @ar }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy  
      end

      def assessment_record_params
        params.require(:assessment_record).permit(:id, :meta, :title, :record, :recordable)
      end
      
    end
  end
end