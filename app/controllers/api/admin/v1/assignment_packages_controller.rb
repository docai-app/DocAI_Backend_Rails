# frozen_string_literal: true

module Api
  module Admin
    module V1
      class AssignmentPackagesController < ApplicationController
        before_action :set_assignment_package, only: %i[show destroy retry_generation]

        def index
          packages = AssignmentPackage.includes(:general_user, :learning_path_template).order(created_at: :desc)
          packages = packages.where(status: params[:status]) if params[:status].present?
          packages = packages.where(general_user_id: params[:general_user_id]) if params[:general_user_id].present?
          packages = packages.where(learning_path_template_id: params[:learning_path_template_id]) if params[:learning_path_template_id].present?

          render json: {
            success: true,
            assignment_packages: packages.map { |package| admin_list_json(package) }
          }, status: :ok
        end

        def show
          render json: { success: true, assignment_package: admin_detail_json(@assignment_package) }, status: :ok
        end

        def destroy
          @assignment_package.destroy!
          render json: { success: true, message: 'AssignmentPackage deleted successfully' }, status: :ok
        end

        def retry_generation
          @assignment_package.update!(status: :generating, error: {})
          AssignmentPackageGenerationJob.perform_async(@assignment_package.id)
          render json: { success: true, assignment_package: admin_detail_json(@assignment_package.reload) }, status: :ok
        end

        private

        def set_assignment_package
          @assignment_package = AssignmentPackage.includes(assignment_package_items: :essay_assignment).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'AssignmentPackage not found' }, status: :not_found
        end

        def admin_list_json(package)
          package.as_list_json.merge(
            student: {
              id: package.general_user.id,
              email: package.general_user.email,
              nickname: package.general_user.nickname
            },
            learning_path_template: package.learning_path_template&.as_student_json
          )
        end

        def admin_detail_json(package)
          admin_list_json(package).merge(
            source_conversation: package.source_conversation,
            dify_request: package.dify_request,
            dify_response: package.dify_response,
            error: package.error,
            items: package.assignment_package_items.map(&:as_json_for_package)
          )
        end
      end
    end
  end
end
