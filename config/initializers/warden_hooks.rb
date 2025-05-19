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

      # 實例化 Ahoy::Tracker
      # 注意：如果 controller 為 nil，Ahoy::Tracker 仍然可以工作，
      # 它會嘗試從 request 中獲取必要信息。
      # Ahoy 的 general_user 方法 (在 config/initializers/ahoy.rb 中定義的) 仍然會被調用
      # 並且因為我們在 Ahoy::Store 中定義了 general_user 方法依賴 controller.current_general_user，
      # 所以我們需要確保在一個有 controller 上下文的地方調用。
      # 一個更可靠的方法是，如果你的 ApiController 混入了 Ahoy::Controller (通常會自動發生)，
      # 並且 current_general_user 已經被設置。

      # 考慮到 after_authentication hook 可能在控制器實例完全建立前觸發，
      # 或者在非控制器上下文中 (理論上 warden 也可以用於其他 rack app)，
      # 一個更安全的方式可能是直接使用 general_user 對象來 track，
      # 依賴於 Ahoy::Store 中定義的 general_user 方法來將 event 關聯到正確的 visit。
      # Ahoy 會嘗試從 Thread.current[:ahoy] 獲取 tracker，
      # 如果中間件正確設置了它。

      if request.present?
        # 嘗試獲取或創建一個 Ahoy Tracker 實例
        # Ahoy 中間件通常會將 tracker 存儲在 request.env['ahoy']
        tracker = request.env['ahoy'] || Ahoy::Tracker.new(request:)

        # 將當前登入用戶與 tracker 關聯
        # 這會確保 visit 和 event 能正確記錄 user_id
        tracker.authenticate(general_user)

        # 使用 tracker 實例來追蹤事件
        event_name = 'GeneralUser Signed In'
        properties = { strategy: opts[:strategy].to_s, scope: opts[:scope].to_s }
        tracker.track(event_name, properties)

        Rails.logger.info "[WardenHook] Tracked '#{event_name}' for #{general_user.email} with properties: #{properties.inspect}"
      else
        Rails.logger.warn "[WardenHook] Could not track 'GeneralUser Signed In' for #{general_user.email} due to missing request object in auth proxy."
      end
    rescue StandardError => e
      Rails.logger.error "[WardenHook] Error tracking 'GeneralUser Signed In' for #{general_user.email}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end
