# frozen_string_literal: true

# 基本的 Ahoy::Store 定義，繼承自預設的 DatabaseStore。
# 這樣 Ahoy::Tracker 就能找到 Ahoy::Store 類別。
# 如果不需要自訂 user 方法或 authenticate 方法，可以將其內部留空或移除。
class Ahoy::Store < Ahoy::DatabaseStore
  # 目前將內部留空，以使用 Ahoy::DatabaseStore 的預設行為。

  # 如果需要自訂 user 方法，可以取消註解以下程式碼：
  # def user
  #   controller.current_general_user if controller && controller.respond_to?(:current_general_user, true)
  # end

  # authenticate 方法通常不需要在這裡自訂，
  # 因為 Ahoy::DatabaseStore 的父類行為已經處理了使用者關聯。
  # def authenticate(data)
  #   super(data)
  # end
end

# -- 基本 Ahoy 配置 --

# API Only 模式
# 對於 API-only 應用，Ahoy 不會自動注入 JavaScript tracker。
Ahoy.api_only = true

# Visit 追蹤
# :when_needed - 僅在需要時（例如追蹤事件或用戶登錄時）創建 Visit。推薦用於 API。
# :immediately - 每個請求都嘗試創建或更新 Visit（可能會更頻繁地寫入數據庫）。
Ahoy.server_side_visits = true

# 異步處理 Visit 和 Event 記錄
# 將數據庫寫入操作放到後台隊列，以避免阻塞主請求。
# Ahoy 5.x 默認 track_events_immediately = true (同步處理事件)。
# 如果希望事件也異步處理，可以取消下面這行的註釋：
# Ahoy.track_events_immediately = false

# 後台任務隊列名稱 (確保您的 Sidekiq 監聽此隊列)
Ahoy.job_queue = :ahoy # 您可以根據項目的隊列策略命名，例如 :default, :background_jobs

# 開發環境日誌
# 在開發模式下，設置為 false 可以看到 Ahoy 的調試日誌，有助於排查問題。
# 生產環境下通常設為 true。
Ahoy.quiet = !Rails.env.development?

# 追蹤機器人（可以根據需要禁用）
Ahoy.track_bots = true

# 默認的訪問持續時間（4小時）
# Ahoy.visit_duration = 4.hours

# 可以自定義訪客的持續時間
# Ahoy.visitor_duration = 2.years

# 啟用IP掩碼化以提高隱私保護
# Ahoy.mask_ips = true

# 設置Cookie選項，比如跨域支持
# Ahoy.cookie_domain = :all

# 為了便於測試和開發，我們可以在開發環境中禁用某些安全措施
# if Rails.env.development?
#   Ahoy.cookie_options = {same_site: :lax}
# end

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

# set to true for geocoding (and add the geocoder gem to your Gemfile)
# we recommend configuring local geocoding as well
# see https://github.com/ankane/ahoy#geocoding
Ahoy.geocode = false
