# frozen_string_literal: true

module Api
  module School
    module V1
      class PasswordManagersController < SchoolApiController
        before_action :require_owner!

        def index
          accounts = managers.order(created_at: :desc).page(params[:page] || 1).per(20)
          render json: { success: true, data: { accounts: accounts.map { |u| account_json(u) }, pagination: pagination_meta(accounts) } }
        end

        def classes
          years = current_school.school_academic_years.where(status: :active).order(start_date: :desc)
          rows = years.map do |year|
            { id: year.id, name: year.name,
              classes: StudentEnrollment.where(school_academic_year_id: year.id, status: :active)
                                        .where.not(class_name: [nil, '']).distinct.order(:class_name).pluck(:class_name) }
          end
          render json: { success: true, data: { academic_years: rows } }
        end

        def create
          grants = validated_grants
          raise ArgumentError, '請填寫老師姓名。' if params[:nickname].to_s.strip.blank?
          raise ArgumentError, '密碼至少需要 8 個字元。' if params[:password].to_s.length < 8
          user = GeneralUser.new(email: params.require(:email).to_s.strip.downcase,
                                 nickname: params.require(:nickname).to_s.strip,
                                 password: params.require(:password), school_id: current_school.id,
                                 meta: { 'aienglish_role' => 'school_password_manager', 'aienglish_features_list' => [],
                                         'school_password_access' => { 'enabled' => true, 'grants' => grants,
                                           'created_by_id' => current_general_user.id, 'revision' => SecureRandom.uuid,
                                           'session_version' => SecureRandom.uuid } }, konnecai_tokens: {})
          GeneralUser.transaction do
            user.save!
            user.create_energy!(value: 100) unless user.energy
            audit!(user, 'password_manager_created')
          end
          render json: { success: true, data: { account: account_json(user) } }, status: :created
        rescue ArgumentError, ActionController::ParameterMissing => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        rescue ActiveRecord::RecordInvalid
          render json: { success: false, error: '無法建立帳號，請確認帳號未被使用及密碼符合要求。' }, status: :unprocessable_entity
        rescue ActiveRecord::RecordNotUnique
          render json: { success: false, error: '此登入帳號已被使用。' }, status: :conflict
        end

        def update
          user = managers.find(params[:id])
          user.with_lock do
            access = user.school_password_access.deep_dup
            unless params[:revision].present? && params[:revision] == access['revision']
              return render json: { success: false, error: '帳號已被更新，請重新載入後再修改。' }, status: :conflict
            end
            access['grants'] = validated_grants if params.key?(:grants)
            if params.key?(:enabled)
              raise ArgumentError, '啟用狀態必須為 true 或 false。' unless [true, false].include?(params[:enabled])
              access['enabled'] = params[:enabled]
              access['session_version'] = SecureRandom.uuid
            end
            if params[:password].present?
              raise ArgumentError, '密碼至少需要 8 個字元。' if params[:password].to_s.length < 8
              user.password = params[:password]
              access['session_version'] = SecureRandom.uuid
            end
            if params.key?(:nickname)
              raise ArgumentError, '請填寫老師姓名。' if params[:nickname].to_s.strip.blank?
              user.nickname = params[:nickname].to_s.strip
            end
            access['revision'] = SecureRandom.uuid
            user.meta = user.meta.merge('school_password_access' => access)
            user.save!
            audit!(user, 'password_manager_updated')
          end
          render json: { success: true, data: { account: account_json(user) } }
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'Account not found.' }, status: :not_found
        rescue ArgumentError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        rescue ActiveRecord::RecordInvalid
          render json: { success: false, error: '儲存失敗，請檢查姓名及密碼。' }, status: :unprocessable_entity
        end

        private

        def require_owner!
          return if current_general_user.portal_school_admin?
          render json: { success: false, error: 'Forbidden.' }, status: :forbidden
        end

        def managers
          GeneralUser.where(school_id: current_school.id).where("meta->>'aienglish_role' = ?", 'school_password_manager')
        end

        def validated_grants
          grants = params[:grants]
          raise ArgumentError, '班級授權必須為清單。' unless grants.is_a?(Array) && grants.size <= 300
          grants.map do |grant|
            raise ArgumentError, '班級授權格式錯誤。' unless grant.is_a?(Hash) || grant.is_a?(ActionController::Parameters)
            year = current_school.school_academic_years.where(status: :active).find_by(id: grant[:school_academic_year_id])
            name = grant[:class_name]
            unless year && name.is_a?(String) && name.present? &&
                   StudentEnrollment.where(school_academic_year_id: year.id, class_name: name, status: :active).exists?
              raise ArgumentError, '只能授權本校當前學年內的班級。'
            end
            { 'school_academic_year_id' => year.id, 'class_name' => name }
          end.uniq
        end

        def account_json(user)
          { id: user.id, email: user.email, nickname: user.nickname,
            enabled: user.school_password_access['enabled'] == true,
            grants: user.school_password_grants, revision: user.school_password_access['revision'] }
        end

        def audit!(user, action)
          SchoolPortal::AuditLogger.log!(actor: current_general_user, school: current_school, action: action,
                                        target: user, metadata: { enabled: user.school_password_access['enabled'],
                                                                 grants: user.school_password_grants }, request: request)
        end
      end
    end
  end
end
