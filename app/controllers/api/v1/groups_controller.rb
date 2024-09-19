# frozen_string_literal: true

# app/controllers/groups_controller.rb
module Api
  module V1
    class GroupsController < ApiController
      before_action :set_group, only: %i[show edit update destroy add_students remove_students]

      # POST /groups/:id/add_students
      def add_students
        if params[:student_ids].nil? || !params[:student_ids].is_a?(Array)
          render json: { error: 'Student IDs are required and should be an array' }, status: :unprocessable_entity
          return
        end

        students = GeneralUser.where(id: params[:student_ids])
        missing_ids = params[:student_ids] - students.pluck(:id)

        if missing_ids.any?
          render json: { error: "Students not found for IDs: #{missing_ids.join(', ')}" }, status: :not_found
          return
        end

        students.each do |student|
          @group.memberships.find_or_create_by(general_user: student)
        end

        render json: { message: 'Students added to group successfully' }, status: :ok
      end

      # DELETE /groups/:id/remove_students
      def remove_students
        if params[:student_ids].nil? || !params[:student_ids].is_a?(Array)
          render json: { error: 'Student IDs are required and should be an array' }, status: :unprocessable_entity
          return
        end

        students = GeneralUser.where(id: params[:student_ids])
        missing_ids = params[:student_ids] - students.pluck(:id)

        if missing_ids.any?
          render json: { error: "Students not found for IDs: #{missing_ids.join(', ')}" }, status: :not_found
          return
        end

        memberships = @group.memberships.where(general_user: students)
        if memberships.destroy_all
          render json: { message: 'Students removed from group successfully' }, status: :ok
        else
          render json: { error: 'Failed to remove students from group' }, status: :unprocessable_entity
        end
      end

      def index
        @groups = if current_general_user.present?
                    Group.where(owner_id: current_general_user.id)
                  else
                    []
                  end
        render json: { success: true, groups: @groups }, status: :ok
      end

      # GET /groups/:id
      def show
        render json: { success: true, group: @group.as_json(include: :general_users) }, status: :ok
      end

      def new
        @group = Group.new
      end

      def create
        @group = Group.new(group_params)
        @group.owner_id = current_general_user.id
        # 只有 teacher 可以開 group
        # binding.pry
        return json_fail('you are not a teacher') unless current_general_user.has_role?('teacher')

        if @group.save
          json_success(@group)
        else
          json_fail('cannot save')
        end
      end

      def edit; end

      def update
        if @group.update(group_params)
          json_success(@group)
        else
          json_fail('cannot save')
        end
      end

      def destroy
        @group.destroy
        json_success
      end

      private

      def set_group
        @group = Group.find(params[:id])
      end

      def group_params
        params.require(:group).permit(:name)
      end
    end
  end
end
