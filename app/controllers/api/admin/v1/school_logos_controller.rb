# frozen_string_literal: true

module Api
  module Admin
    module V1
      # 學校 Logo 控制器
      # 提供上傳和刪除學校 logo 的 API 端點
      # 遵循關注點分離原則，專注於處理學校 logo 相關操作
      class SchoolLogosController < AdminApiController
        before_action :set_school

        # PUT /admin/v1/schools/:code/logo
        # 上傳學校 logo
        # @param code [String] 學校代碼
        # @param logo [File] 上傳的 logo 文件
        # @return [JSON] 操作結果及更新後的 logo URL
        def update
          # 驗證是否提供了 logo 文件
          unless params[:logo].present?
            return render json: {
              status: 'error',
              errors: ['未提供 logo 文件']
            }, status: :unprocessable_entity
          end

          # 檢查文件類型，確保安全性
          unless valid_content_type?(params[:logo])
            return render json: {
              status: 'error',
              errors: ['不支持的文件格式，請上傳 PNG, JPEG, JPG, GIF, WEBP 或 SVG 格式的圖片']
            }, status: :unprocessable_entity
          end

          # 如果已經有 logo，先刪除舊的以節省存儲空間
          @school.logo.purge if @school.logo.attached?

          # 附加新 logo
          @school.logo.attach(params[:logo])

          if @school.save
            # 返回成功信息和 logo URLs（不同尺寸變體）
            render json: {
              status: 'success',
              message: "成功更新學校 #{@school.name} 的 logo",
              data: {
                has_logo: true,
                original_url: @school.logo_url,
                thumbnail_url: @school.logo_thumbnail_url,
                small_url: @school.logo_small_url,
                large_url: @school.logo_large_url,
                square_url: @school.logo_square_url
              }
            }
          else
            # 返回錯誤信息
            render json: {
              status: 'error',
              errors: @school.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # DELETE /admin/v1/schools/:code/logo
        # 刪除學校 logo
        # @param code [String] 學校代碼
        # @return [JSON] 操作結果
        def destroy
          # 檢查是否有 logo 可刪除
          unless @school.logo.attached?
            return render json: {
              status: 'error',
              errors: ['該學校沒有 logo']
            }, status: :not_found
          end

          # 執行刪除操作
          if @school.logo.purge
            render json: {
              status: 'success',
              message: "成功刪除學校 #{@school.name} 的 logo"
            }
          else
            render json: {
              status: 'error',
              errors: ['刪除 logo 失敗']
            }, status: :unprocessable_entity
          end
        end

        private

        # 設置當前操作的學校
        # @param code [String] 從路由參數中獲取的學校代碼
        def set_school
          @school = School.find_by(code: params[:code])

          # 如果找不到學校，返回 404 錯誤
          return if @school

          render json: {
            status: 'error',
            errors: ["找不到學校代碼: #{params[:code]}"]
          }, status: :not_found
        end

        # 驗證上傳文件的內容類型
        # @param file [ActionDispatch::Http::UploadedFile] 上傳的文件
        # @return [Boolean] 文件類型是否有效
        def valid_content_type?(file)
          valid_types = %w[image/png image/jpeg image/jpg image/gif image/webp image/svg+xml]
          valid_types.include?(file.content_type)
        end
      end
    end
  end
end
