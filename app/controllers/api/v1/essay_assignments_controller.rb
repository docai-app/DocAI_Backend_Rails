# frozen_string_literal: true

module Api
  module V1
    class EssayAssignmentsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment, only: %i[update destroy]

      def index
        @essay_assignments = current_general_user.essay_assignments.select(:id, :number_of_submission, :rubric, :topic,
                                                                           :created_at, :updated_at, :code, :assignment)
        @essay_assignments = Kaminari.paginate_array(@essay_assignments).page(params[:page])
        render json: { success: true, essay_assignments: @essay_assignments, meta: pagination_meta(@essay_assignments) },
               status: :ok
      end

      def show_only
        @essay_assignment = EssayAssignment.find_by!(code: params[:id])
        render json: { success: true, essay_assignment: @essay_assignment }
      end

      def show
        @essay_assignment = EssayAssignment.find(params[:id])

        @essay_gradings = @essay_assignment.essay_gradings
                                           .joins(:general_user)
                                           .select('essay_gradings.id, essay_gradings.general_user_id, essay_gradings.created_at, essay_gradings.updated_at, essay_gradings.status, COALESCE(essay_gradings.grading ->> \'number_of_suggestion\', \'null\') AS number_of_suggestion, general_users.nickname, general_users.banbie, general_users.class_no')
                                           .includes(:general_user)

        render json: {
          success: true,
          essay_assignment: @essay_assignment,
          essay_gradings: @essay_gradings.map do |eg|
            {
              id: eg.id,
              general_user: {
                id: eg.general_user_id,
                nickname: eg.nickname,
                class_name: eg.banbie,
                class_no: eg.class_no
              },
              created_at: eg.created_at,
              updated_at: eg.updated_at,
              status: eg.status,
              number_of_suggestion: eg['number_of_suggestion'] == 'null' ? nil : eg['number_of_suggestion']
            }
          end
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def create
        @essay_assignment = EssayAssignment.new(essay_assignment_params)
        @essay_assignment.general_user_id = current_general_user.id
        if @essay_assignment.save
          render json: { success: true, essay_assignment: @essay_assignment }, status: :created
        else
          render json: { success: false, errors: @essay_assignment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @essay_assignment.update(essay_assignment_params)
          render json: { success: true, essay_assignment: @essay_assignment }, status: :ok
        else
          render json: { success: false, errors: @essay_assignment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @essay_assignment.destroy
        render json: { success: true, message: 'EssayAssignment deleted successfully' }, status: :ok
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def essay_assignment_params
        params.require(:essay_assignment).permit(:topic, :assignment, rubric: %i[name app_key])
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
