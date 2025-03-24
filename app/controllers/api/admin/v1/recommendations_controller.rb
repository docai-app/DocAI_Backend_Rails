# frozen_string_literal: true

# 這是一份僅用於教學目的的參考文件，展示兩種控制器設計方案的對比
# 不應在實際應用中使用此代碼

# ==========================================
# 方案一：大一統控制器（Monolithic Controller）
# ==========================================

module Example1
  class SchoolsController < AdminApiController
    # 基本的 CRUD 操作（省略具體實現）
    def index; end
    def show; end
    def create; end
    def update; end
    def destroy; end

    # 學生管理
    def assign_students; end
    def remove_students; end

    # 教師管理
    def assign_teachers; end
    def remove_teachers; end

    # 統計功能
    def student_stats; end
    def teacher_stats; end

    # Logo 管理 - 集成到同一個控制器
    def update_logo
      # 實現上傳 logo 的邏輯
    end

    def remove_logo
      # 實現刪除 logo 的邏輯
    end

    # 可能還有其他功能...
    # 隨著功能增加，該控制器會變得越來越大
  end
end

# ==========================================
# 方案二：關注點分離（Separation of Concerns）
# ==========================================

module Example2
  # 核心學校管理控制器
  class SchoolsController < AdminApiController
    # 基本的 CRUD 操作
    def index; end
    def show; end
    def create; end
    def update; end
    def destroy; end
  end

  # 學生管理專用控制器
  class SchoolStudentsController < AdminApiController
    def index; end
    def assign; end
    def remove; end
    def stats; end
  end

  # 教師管理專用控制器
  class SchoolTeachersController < AdminApiController
    def index; end
    def assign; end
    def remove; end
    def stats; end
  end

  # Logo 管理專用控制器
  class SchoolLogosController < AdminApiController
    def update; end
    def destroy; end
  end

  # 每個控制器都專注於自己的職責
  # 更容易維護和擴展
end

# ==========================================
# 業界案例分析
# ==========================================

# 1. GitHub - 使用關注點分離
#    - UsersController 處理用戶基本操作
#    - UserAvatarsController 處理頭像
#    - UserSettingsController 處理設置

# 2. Shopify - 使用關注點分離
#    - ProductsController 處理產品基本操作
#    - ProductImagesController 處理產品圖片
#    - ProductVariantsController 處理產品變體

# 3. Basecamp - 使用關注點分離
#    - PeopleController 處理人員基本操作
#    - AvatarsController 處理頭像
#    - PermissionsController 處理權限

# 結論：大型專業 Rails 應用普遍采用關注點分離原則，
# 將不同功能分離為專門的控制器，以提高代碼可維護性。
