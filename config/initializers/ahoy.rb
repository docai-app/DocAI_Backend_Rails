class Ahoy::Store < Ahoy::DatabaseStore
  # 自定義 Ahoy 如何找到當前用戶
  # 假設您的 Devise 用戶模型是 GeneralUser，並且控制器中有 current_general_user 方法
  def general_user
    # 在 API 模式下，controller 可能通過 request.env['action_controller.instance'] 獲取
    # 或者，如果您的 ApiController 混入了 Ahoy::Controller，可以直接使用 controller.current_general_user
    if controller.respond_to?(:current_general_user, true) # 第二個參數 true 表示也檢查私有方法
      controller.send(:current_general_user) # 使用 send 以調用可能的私有方法
    else
      nil
    end
  end

  # 可選：如果您的應用程序在負載均衡器或反向代理後面，
  # 您可能需要自定義如何獲取真實的用戶 IP 地址。
  # def visit_properties
  #   super.merge(ip: request.remote_ip) # 這是 Rails 的標準方式
  #   # 或者，如果 IP 在特定的 header 中，例如：
  #   # super.merge(ip: request.headers["X-Forwarded-For"]&.split(',')&.first&.strip)
  # end
end

# -- 基本 Ahoy 配置 --

# API Only 模式
# 對於 API-only 應用，Ahoy 不會自動注入 JavaScript tracker。
Ahoy.api_only = true

# Visit 追蹤
# :when_needed - 僅在需要時（例如追蹤事件或用戶登錄時）創建 Visit。推薦用於 API。
# :immediately - 每個請求都嘗試創建或更新 Visit（可能會更頻繁地寫入數據庫）。
Ahoy.server_side_visits = :when_needed

# 異步處理 Visit 和 Event 記錄
# 將數據庫寫入操作放到後台隊列，以避免阻塞主請求。
Ahoy.track_visits_immediately = false
# Ahoy 5.x 默認 track_events_immediately = true, 所以如果想異步，需要明確設置為 false
# Ahoy.track_events_immediately = false # 取決於您Ahoy的版本，先不加，如果事件處理慢再考慮

# 後台任務隊列名稱 (確保您的 Sidekiq 監聽此隊列)
Ahoy.job_queue = :ahoy # 您可以根據項目的隊列策略命名，例如 :default, :background_jobs

# 開發環境日誌
# 在開發模式下，設置為 false 可以看到 Ahoy 的調試日誌，有助於排查問題。
# 生產環境下通常設為 true。
Ahoy.quiet = Rails.env.production?

# 地理位置 (可選，如果需要)
# Ahoy.geocode = :async # :async 表示異步地理編碼 (推薦)
                     # false 表示禁用地理編碼
                     # true 表示同步地理編碼 (不推薦，可能阻塞請求)
# 如果啟用了地理編碼 (非 false)，您需要在 config/initializers/geocoder.rb 中配置 Geocoder。
# 例如，使用本地 MaxMind GeoLite2 數據庫：
# Geocoder.configure(
#   lookup: :geoip2,
#   geoip2: {
#     file: Rails.root.join('db', 'GeoLite2-City.mmdb') # 您需要下載並放置此文件
#   },
#   # ... 其他 Geocoder 配置 ...
# )

# 其他高級配置 (通常保持默認即可)
# Ahoy.visit_duration = 4.hours # Visit 的持續時間
# Ahoy.visitor_token_header = "Ahoy-Visitor" # 用於 API 的 Visitor token header
# Ahoy.visit_token_header = "Ahoy-Visit"     # 用於 API 的 Visit token header
# Ahoy.cookie_domain = :all # Cookie 作用域
# Ahoy.cookies = true # API Only 模式下，如果客戶端是瀏覽器，仍然可以依賴 Cookie；
                    # 如果是非瀏覽器客戶端，則需要客戶端在 Header 中傳遞 tokens。
