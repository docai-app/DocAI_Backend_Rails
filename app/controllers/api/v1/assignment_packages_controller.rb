# frozen_string_literal: true

module Api
  module V1
    class AssignmentPackagesController < ApiController
      before_action :authenticate_general_user!

      def index
        packages = current_general_user.assignment_packages
                                       .includes(:learning_path_template)
                                       .order(created_at: :desc)
        packages = packages.where(status: params[:status]) if params[:status].present?

        render json: { success: true, assignment_packages: packages.map(&:as_list_json) }, status: :ok
      end

      def show
        package = current_general_user.assignment_packages.includes(assignment_package_items: :essay_assignment).find(params[:id])
        render json: { success: true, assignment_package: package.as_detail_json }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'AssignmentPackage not found' }, status: :not_found
      end

      def create
        template = LearningPathTemplate.visible_to_students.find(package_params[:learning_path_template_id])
        conversation = normalized_conversation_payload(package_params[:conversation])

        package = current_general_user.assignment_packages.create!(
          learning_path_template: template,
          learner_profile_id: package_params[:learner_profile_id],
          title: 'Generating learning package',
          description: template.description,
          status: :generating,
          source_conversation: conversation,
          progress: default_progress
        )

        AssignmentPackageGenerationJob.perform_async(package.id)

        render json: { success: true, assignment_package: package.as_list_json }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'LearningPathTemplate not found' }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActionController::ParameterMissing => e
        render json: { success: false, error: e.message }, status: :bad_request
      end

      def destroy
        package = current_general_user.assignment_packages.find(params[:id])
        unless package.failed?
          render json: { success: false, error: 'Only failed assignment packages can be deleted by students.' },
                 status: :unprocessable_entity
          return
        end

        package.destroy!
        render json: { success: true, message: 'AssignmentPackage deleted successfully' }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'AssignmentPackage not found' }, status: :not_found
      end

      def start_item
        package = current_general_user.assignment_packages.includes(assignment_package_items: :essay_assignment).find(params[:id])
        item = package.assignment_package_items.find(params[:item_id])

        if item.locked?
          render json: { success: false, error: 'AssignmentPackageItem is locked.' }, status: :forbidden
          return
        end

        render json: {
          success: true,
          assignment_package_item: item.as_json_for_package,
          essay_assignment: item.essay_assignment.as_list_json
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'AssignmentPackageItem not found' }, status: :not_found
      end

      private

      def package_params
        params.require(:assignment_package).permit(
          :learning_path_template_id,
          :learner_profile_id,
          conversation: [
            :conversation_id,
            :transcript,
            :started_at,
            :ended_at,
            :duration_seconds,
            { student_audio_urls: [] },
            { ai_audio_urls: [] },
            { raw_rtc_payload: {} },
            {
              turns: [
                :turn_index,
                :index,
                :role,
                :text,
                :audio_url,
                :started_at,
                :ended_at,
                :duration_seconds
              ]
            }
          ]
        )
      end

      def normalized_conversation_payload(raw_payload)
        TalkLabSpeaking::ConversationPayloadBuilder.new(raw_payload || {}).call
      end

      def default_progress
        {
          'total_items' => 0,
          'completed_items' => 0,
          'current_position' => nil,
          'completion_percentage' => 0
        }
      end
    end
  end
end
