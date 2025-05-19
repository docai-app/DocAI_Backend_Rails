Warden::Manager.after_authentication do |general_user, auth, opts|
  # user 是登入成功的用戶對象
  # auth 是 Warden::Proxy 對象，可以訪問 request (auth.request)
  # opts 包含如 :scope 和 :event 等信息

  # 我們只關心 GeneralUser 的成功登入
  if general_user.is_a?(GeneralUser) && opts[:event] == :authentication
    begin
      # 嘗試獲取控制器實例和請求對象
      # 在 Rails API 模式下，控制器實例可能不總是在 env 中直接可用
      # 但 request 對象應該是可用的
      request = auth.request

      if request.present?
        # 嘗試獲取或創建一個 Ahoy Tracker 實例
        # Ahoy 中間件通常會將 tracker 存儲在 request.env['ahoy']
        tracker = request.env['ahoy'] || Ahoy::Tracker.new(request:)

        Rails.logger.info "[WardenHook] Before authenticate, visit_token: #{tracker.visit_token}, visit.user_id: #{tracker.visit&.user_id}, visit.id: #{tracker.visit&.id}"
        Rails.logger.info "[WardenHook] Authenticating with general_user ID: #{general_user.id}"

        tracker.authenticate(general_user) # 關鍵步驟，將 visit 與 user 關聯

        # 在 authenticate 之後，重新從 tracker 獲取 visit，因為 authenticate 可能會修改它或其關聯
        # 或者直接從資料庫查詢最新的 visit 狀態
        current_visit_from_tracker = tracker.visit
        Rails.logger.info "[WardenHook] After authenticate, visit_token from tracker: #{current_visit_from_tracker&.visit_token}, visit.user_id from tracker: #{current_visit_from_tracker&.user_id}, visit.id from tracker: #{current_visit_from_tracker&.id}"

        # 為了更確定，可以嘗試從資料庫直接讀取 visit
        if current_visit_from_tracker&.visit_token
          db_visit = Ahoy::Visit.find_by(visit_token: current_visit_from_tracker.visit_token)
          Rails.logger.info "[WardenHook] After authenticate, visit user_id from DB query: #{db_visit&.user_id}"
        end

        event_name = 'GeneralUser Signed In'
        # 屬性中不包含 user，讓 Ahoy 從已 authenticate 的 visit 中獲取 user 關聯
        event_properties = {
          strategy: opts[:strategy].to_s,
          scope: opts[:scope].to_s
        }
        tracker.track(event_name, event_properties)

        Rails.logger.info "[WardenHook] Tracked '#{event_name}' for #{general_user.email} with properties: #{event_properties.inspect}"
      else
        Rails.logger.warn "[WardenHook] Could not track 'GeneralUser Signed In' for #{general_user.email} due to missing request object in auth proxy."
      end
    rescue StandardError => e
      Rails.logger.error "[WardenHook] Error tracking 'GeneralUser Signed In' for #{general_user.email}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end
