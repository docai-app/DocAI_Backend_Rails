# frozen_string_literal: true

module Api
  module School
    module V1
      class AuditLogsController < SchoolApiController
        def index
          logs = SchoolAdminAuditLog.where(school_id: current_school.id).order(created_at: :desc)
          page = params[:page] || 1
          per_page = (params[:per_page] || 30).to_i.clamp(1, 100)
          logs = logs.page(page).per(per_page)

          rows = logs.map do |l|
            {
              id: l.id,
              operator_id: l.actor_id,
              action: l.action,
              target_type: l.target_type,
              target_id: l.target_id,
              target_name: l.metadata['target_name'],
              time: l.created_at,
              ip: l.ip_address,
              metadata: l.metadata
            }
          end

          render json: {
            success: true,
            data: {
              logs: rows,
              pagination: pagination_meta(logs)
            }
          }, status: :ok
        end

        def create
          audit_action = params[:audit_action].to_s.presence
          unless audit_action && SchoolPortal::AUDIT_ACTIONS.include?(audit_action)
            return render json: { success: false, error: 'Invalid audit_action' }, status: :unprocessable_entity
          end

          meta_param = params[:metadata]
          meta = case meta_param
                 when ActionController::Parameters
                   meta_param.permit!.to_h
                 when Hash
                   meta_param
                 else
                   {}
                 end

          SchoolPortal::AuditLogger.log!(
            actor: current_general_user,
            school: current_school,
            action: audit_action,
            metadata: meta,
            request: request
          )

          render json: { success: true }, status: :created
        end
      end
    end
  end
end
