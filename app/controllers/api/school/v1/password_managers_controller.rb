# frozen_string_literal: true

module Api
  module School
    module V1
      class PasswordManagersController < SchoolApiController
        before_action :require_owner!

        def index
          accounts = managers.where("meta->'school_password_access'->>'deleted_at' IS NULL").order(created_at: :desc).page(params[:page] || 1).per(20)
          render json: { success: true, data: { accounts: accounts.map { |u| account_json(u) }, pagination: pagination_meta(accounts) } }
        end

        def classes
          years = current_school.school_academic_years.where(status: :active).order(start_date: :desc)
          classes_by_year = StudentEnrollment.where(school_academic_year_id: years.select(:id), status: :active)
            .where.not(class_name: [nil, '']).distinct.order(:class_name)
            .pluck(:school_academic_year_id, :class_name).group_by(&:first)
          rows = years.map do |year|
            { id: year.id, name: year.name,
              classes: (classes_by_year[year.id] || []).map(&:last) }
          end
          render json: { success: true, data: { academic_years: rows } }
        end

        def teachers
          scope = eligible_teachers.where("meta->'school_password_access'->>'school_id' IS NULL OR meta->'school_password_access'->>'deleted_at' IS NOT NULL")
          scope = scope.merge(GeneralUser.search_query(params[:keyword])) if params[:keyword].present?
          rows = scope.select(:id, :email, :nickname).distinct.order(:nickname, :id).page(params[:page] || 1).per(20)
          render json: { success: true, data: { teachers: rows.map { |u| { id: u.id, email: u.email, nickname: u.nickname } }, pagination: pagination_meta(rows) } }
        end

        def create
          return create_from_teacher if params.key?(:teacher_id)
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
            raise ActiveRecord::RecordNotFound if access['deleted_at'].present?
            unless params[:revision].present? && params[:revision] == access['revision']
              return render json: { success: false, error: '帳號已被更新，請重新載入後再修改。' }, status: :conflict
            end
            if user.linked_school_password_teacher? && %i[email nickname password].any? { |field| params.key?(field) }
              raise ArgumentError, '老師沿用原有帳號資料，此處只能修改後台權限。'
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

        # Keep the identity and audit history; never cascade-delete student/teaching data.
        def destroy
          user = managers.find(params[:id])
          user.with_lock do
            access = user.school_password_access.deep_dup
            return head :no_content if access['deleted_at'].present?
            unless params[:revision].present? && params[:revision] == access['revision']
              return render json: { success: false, error: '帳號已被更新，請重新載入後再刪除。' }, status: :conflict
            end
            access.merge!('enabled' => false, 'grants' => [], 'deleted_at' => Time.current.iso8601,
                          'revision' => SecureRandom.uuid, 'session_version' => SecureRandom.uuid)
            user.update!(meta: user.meta.merge('school_password_access' => access))
            audit!(user, 'password_manager_deleted')
          end
          head :no_content
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'Account not found.' }, status: :not_found
        end

        private

        def create_from_teacher
          raise ArgumentError, '請從老師名單選擇，不需填寫姓名、Email 或密碼。' if %i[email nickname password].any? { |field| params.key?(field) }
          grants = validated_grants
          user = eligible_teachers.find(params.require(:teacher_id))
          user.with_lock do
            raise ActiveRecord::RecordNotFound unless eligible_teachers.where(id: user.id).exists?
            access = user.school_password_access
            if access['school_id'].present? && access['deleted_at'].blank?
              return render json: { success: false, error: '此老師已有學校後台授權，請重新載入清單。' }, status: :conflict
            end
            user.update!(meta: user.meta.merge('school_password_access' => {
              'school_id' => current_school.id, 'enabled' => true, 'grants' => grants,
              'created_by_id' => current_general_user.id, 'revision' => SecureRandom.uuid,
              'session_version' => SecureRandom.uuid
            }))
            audit!(user, 'password_manager_teacher_authorized')
          end
          render json: { success: true, data: { account: account_json(user) } }, status: :created
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: '老師不在本校目前在職名單，請重新選擇。' }, status: :not_found
        end

        def eligible_teachers
          GeneralUser.where("general_users.meta->>'aienglish_role' = ?", 'teacher')
            .where(id: TeacherAssignment.joins(:school_academic_year).where(status: :active,
              school_academic_years: { school_id: current_school.id, status: SchoolAcademicYear.statuses[:active] }).select(:general_user_id))
        end

        def require_owner!
          return if current_general_user.portal_school_admin?
          render json: { success: false, error: 'Forbidden.' }, status: :forbidden
        end

        def managers
          GeneralUser.where("(school_id = :school_id AND meta->>'aienglish_role' = 'school_password_manager') OR (meta->>'aienglish_role' = 'teacher' AND meta->'school_password_access'->>'school_id' = :school_id)", school_id: current_school.id)
        end

        def validated_grants
          grants = params[:grants]
          raise ArgumentError, '班級授權必須為清單。' unless grants.is_a?(Array) && grants.size <= 300
          valid_pairs = StudentEnrollment.where(
            school_academic_year_id: current_school.school_academic_years.where(status: :active).select(:id),
            status: :active
          ).distinct.pluck(:school_academic_year_id, :class_name).to_set
          grants.map do |grant|
            raise ArgumentError, '班級授權格式錯誤。' unless grant.is_a?(Hash) || grant.is_a?(ActionController::Parameters)
            year_id = grant[:school_academic_year_id]
            name = grant[:class_name]
            unless year_id.is_a?(String) && name.is_a?(String) && name.present? && valid_pairs.include?([year_id, name])
              raise ArgumentError, '只能授權本校當前學年內的班級。'
            end
            { 'school_academic_year_id' => year_id, 'class_name' => name }
          end.uniq
        end

        def account_json(user)
          { id: user.id, email: user.email, nickname: user.nickname,
            linked_teacher: user.linked_school_password_teacher?, enabled: user.school_password_access['enabled'] == true,
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
