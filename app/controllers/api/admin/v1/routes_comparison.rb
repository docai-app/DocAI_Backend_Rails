# frozen_string_literal: true

# 這是一份僅用於教學目的的參考文件，展示兩種控制器設計方案對應的路由設計
# 不應在實際應用中使用此代碼

# ==========================================
# 方案一：大一統控制器的路由設計
# ==========================================

# Rails.application.routes.draw do
#   namespace :api do
#     namespace :admin do
#       namespace :v1 do
#         resources :schools, param: :code do
#           member do
#             # 學生相關
#             post :assign_students
#             delete :remove_students
#             get :student_stats
#             get 'academic_years/:academic_year_id/students', to: 'schools#academic_year_students'
#
#             # 教師相關
#             post :assign_teachers
#             delete :remove_teachers
#             get :teacher_stats
#             get 'academic_years/:academic_year_id/teachers', to: 'schools#academic_year_teachers'
#
#             # Logo 相關 - 使用自定義動作
#             put :update_logo
#             delete :remove_logo
#           end
#         end
#       end
#     end
#   end
# end

# 優點：
# - 集中管理所有與學校相關的路由
# - URL 結構簡潔清晰
# - 減少路由文件的複雜度

# 缺點：
# - 隨著功能增加，路由數量快速增長
# - 需要自定義動作（non-RESTful）處理特殊操作
# - 不完全符合 RESTful 資源設計原則

# ==========================================
# 方案二：關注點分離的路由設計
# ==========================================

# Rails.application.routes.draw do
#   namespace :api do
#     namespace :admin do
#       namespace :v1 do
#         # 基本學校資源
#         resources :schools, param: :code
#
#         # 嵌套學生資源
#         resources :schools, param: :code do
#           resources :students, only: [:index, :create, :destroy], controller: 'school_students' do
#             collection do
#               get :stats
#               get 'academic_years/:academic_year_id', to: 'school_students#academic_year_students'
#             end
#           end
#         end
#
#         # 嵌套教師資源
#         resources :schools, param: :code do
#           resources :teachers, only: [:index, :create, :destroy], controller: 'school_teachers' do
#             collection do
#               get :stats
#               get 'academic_years/:academic_year_id', to: 'school_teachers#academic_year_teachers'
#             end
#           end
#         end
#
#         # Logo 資源 - 使用標準 RESTful 動作
#         resources :schools, param: :code do
#           resource :logo, only: [:update, :destroy], controller: 'school_logos'
#         end
#       end
#     end
#   end
# end

# 優點：
# - 完全符合 RESTful 設計原則
# - 路由與控制器的職責明確對應
# - 更容易擴展和維護
# - 支持標準的 HTTP 動詞

# 缺點：
# - 路由文件較複雜
# - URL 可能較長
# - 需要更多的控制器文件

# ==========================================
# 我們實際使用的折中方案：
# ==========================================

# Rails.application.routes.draw do
#   namespace :api do
#     namespace :admin do
#       namespace :v1 do
#         resources :schools, param: :code do
#           # 學校基本操作和大部分功能保留在主控制器
#           member do
#             post :assign_students
#             post :assign_teachers
#             get :student_stats
#             get :teacher_stats
#             get 'academic_years/:academic_year_id/students', to: 'schools#academic_year_students'
#             get 'academic_years/:academic_year_id/teachers', to: 'schools#academic_year_teachers'
#           end
#
#           # 但特殊功能如 logo 操作交由專門控制器處理
#           member do
#             put :logo, to: 'school_logos#update'
#             delete :logo, to: 'school_logos#destroy'
#           end
#         end
#       end
#     end
#   end
# end

# 這種折中方案的優點：
# - 保持主要功能在核心控制器中，增加代碼連貫性
# - 將特殊處理邏輯（如文件上傳）分離到專用控制器
# - 路由結構仍然相對簡潔
# - 符合實際業務需求的平衡方案
