# frozen_string_literal: true

module Api
  module Admin
    module V1
      # 這是一個示範文件，展示如何將 logo 功能整合到 SchoolsController 中
      # 注意：這只是一個參考示例，不應直接使用
      class SchoolsController < AdminApiController
        # 現有的方法...

        # PUT /admin/v1/schools/:code/update_logo
        # 上傳和更新學校 logo
        # @param code [String] 學校代碼
        # @param logo [File] 上傳的 logo 文件
        # @return [JSON] 操作結果
        def update_logo
          # 使用與常規更新不同的方法名稱，避免與 update 方法衝突
          set_school

          # 驗證文件存在
          unless params[:logo].present?
            return render json: {
              status: 'error',
              errors: ['未提供 logo 文件']
            }, status: :unprocessable_entity
          end

          # 驗證文件類型
          unless valid_logo_content_type?(params[:logo])
            return render json: {
              status: 'error',
              errors: ['不支持的文件格式，請上傳 PNG, JPEG, JPG, GIF, WEBP 或 SVG 格式的圖片']
            }, status: :unprocessable_entity
          end

          # 如果已有 logo，先刪除
          @school.logo.purge if @school.logo.attached?

          # 附加新 logo
          @school.logo.attach(params[:logo])

          if @school.save
            render json: {
              status: 'success',
              message: "成功更新學校 #{@school.name} 的 logo",
              data: school_logo_data(@school)
            }
          else
            render json: {
              status: 'error',
              errors: @school.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # DELETE /admin/v1/schools/:code/remove_logo
        # 刪除學校 logo
        # @param code [String] 學校代碼
        # @return [JSON] 操作結果
        def remove_logo
          # 使用與常規刪除不同的方法名稱，避免與 destroy 方法衝突
          set_school

          unless @school.logo.attached?
            return render json: {
              status: 'error',
              errors: ['該學校沒有 logo']
            }, status: :not_found
          end

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

        # 驗證 logo 文件類型
        # @param file [ActionDispatch::Http::UploadedFile] 上傳的文件
        # @return [Boolean] 文件類型是否有效
        def valid_logo_content_type?(file)
          valid_types = %w[image/png image/jpeg image/jpg image/gif image/webp image/svg+xml]
          valid_types.include?(file.content_type)
        end

        # 獲取學校 logo 數據
        # @param school [School] 學校對象
        # @return [Hash] 包含 logo URL 的 Hash
        def school_logo_data(school)
          {
            has_logo: school.logo.attached?,
            original_url: school.logo_url,
            thumbnail_url: school.logo_thumbnail_url,
            small_url: school.logo_small_url,
            large_url: school.logo_large_url,
            square_url: school.logo_square_url
          }
        end

        # 現有的私有方法...
      end
    end
  end
end
