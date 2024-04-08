# frozen_string_literal: true

module Api
  module V1
    class AssessmentRecordsController < ApiController
      include Authenticatable

      before_action :authenticate_general_user!, only: %i[show create update destroy]

      def show_student_assessments
        teacher = current_general_user
        
        # 檢查呢個 student 係咪呢個 teacher 管理先
        unless teacher.linked_students.pluck(:id).include?(params[:uuid])
          return json_fail("not your user")
        end
        
        res = AssessmentRecord.where(recordable_type: "GeneralUser").where(recordable_id: params[:uuid])
        res = Kaminari.paginate_array(res).page(params[:page])
        
        
        render json: { success: true, assessment_records: res, meta: pagination_meta(res) }, status: :ok

      end

      def students
        # 顯示所有管理的學生的總列表
        teacher = current_general_user

        sql = <<-SQL
          SELECT 
            gu.id,
            gu.nickname,
            COUNT(ar.id) AS assessment_count,
            COALESCE(AVG(ar.score), 0) AS average_score
          FROM 
            general_users gu
            LEFT JOIN assessment_records ar ON ar.recordable_type = 'GeneralUser' AND ar.recordable_id = gu.id AND ar.recordable_id IN (:student_ids)
          GROUP BY 
            gu.id, gu.nickname
          order by assessment_count desc;
        SQL

        student_ids = teacher.linked_students.pluck(:id)
        if student_ids.blank?
          return render json: {success: true, student_overview: []}
        end 
        
        results = ActiveRecord::Base.connection.execute(ActiveRecord::Base.send(:sanitize_sql_array, [sql, student_ids: student_ids]))
        # binding.pry
        render json: {success: true, student_overview: results}
        # AssessmentRecord.where(recordable_type: 'GeneralUser', recordable_id: teacher.linked_students.pluck(:id))
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

      def pagination_meta(object)
        {
          current_page: object.current_page,
          next_page: object.next_page,
          prev_page: object.prev_page,
          total_pages: object.total_pages,
          total_count: object.total_count
        }
      end
      
    end
  end
end
