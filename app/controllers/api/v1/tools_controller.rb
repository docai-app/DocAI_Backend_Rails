# frozen_string_literal: true

module Api
  module V1
    class ToolsController < ApiNoauthController

      def upload_directly_ocr
        file = params[:file]

        # 呢道先判斷一下文件的類型先，如果係可以做 ocr 的野，先會去做 ocr
        begin
          file_extension = File.extname(file.original_filename).downcase if file.present?
          allowed_extensions = ['.doc', '.docx', '.pdf', '.jpg', '.jpeg', '.png', '.gif']
          @file_url = AzureService.upload(file) if file.present?

          if allowed_extensions.include?(file_extension)
            ocr_res = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/alpha/ocr", document_url: @file_url)
            content = JSON.parse(ocr_res)['result']
            render json: { success: true, file_url: @file_url, content: }, status: :ok
          else
            render json: { success: true, file_url: @file_url, content: @file_url }, status: :ok
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end

        # begin
        #   @file_url = AzureService.upload(file) if file.present?
        #   ocr_res = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/alpha/ocr", document_url: @file_url)
        #   content = JSON.parse(ocr_res)['result']
        #   render json: { success: true, file_url: @file_url, content: }, status: :ok
        # rescue StandardError => e
        #   render json: { success: false, error: e.message }, status: :unprocessable_entity
        # end
      end

      def text_to_pdf
        content = params[:content]
        begin
          pdfBlob = FormProjectionService.text2Pdf(content)
          blob2Base64 = FormProjectionService.exportImage2Base64(pdfBlob)
          render json: { success: true, pdf: blob2Base64 }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def text_to_png
        content = params[:content]
        begin
          pngBlob = ImageService.html2Png(content)
          blob2Base64 = FormProjectionService.exportImage2Base64(pngBlob)
          render json: { success: true, png: blob2Base64 }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def upload_html_to_pdf
        content = params[:content]
        begin
          pdfBlob = FormProjectionService.text2Pdf(content)
          file_url = AzureService.uploadBlob(pdfBlob, 'chatting_report.pdf', 'application/pdf')
          render json: { success: true, file_url: }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end

      def dify_chatbot_report
        gateway = nil
        local_port = nil

        begin
          gateway, local_port = SshTunnelService.open(
            params[:domain],
            'akali',
            'akl123123'
          )
          
          if gateway.nil? || local_port.nil?
            render json: { error: "SSH tunnel setup failed" }, status: 500
            return
          end
          
          # 使用 PG 库直接连接到 PostgreSQL 数据库
          conn = PG.connect(
            dbname: 'dify',
            user: 'postgres',
            password: 'difyai123456',
            host: 'localhost',
            port: local_port
          )

          # 执行 SQL 查询
          result = conn.exec("SELECT * FROM messages WHERE conversation_id = '#{params[:conversation_id]}'")

          # 转换结果为 JSON
          @items = []
          @items = result.map do |record|
            {"subtitle": record['query'], paragraph: record['answer']}
          end

          @title = params[:title] || "ConversationReport"

          # Render HTML as a string
          # binding.pry
          # puts "Current view paths: #{lookup_context.view_paths.paths.map(&:to_s)}"
          html_string = render_to_string(template: "api/v1/tools/report", formats: [:html], layout: false)
          
          pdfBlob = FormProjectionService.text2Pdf(html_string)
          file_url = AzureService.uploadBlob(pdfBlob, "#{@title}.pdf", 'application/pdf')
          render json: { success: true, file_url: }, status: :ok

          # render "report.html.erb"
          # 渲染结果
          # render json: messages
        ensure
          # 关闭数据库连接
          conn.close if conn

          # 关闭 SSH 隧道
          SshTunnelService.close(gateway) if gateway
        end

        
      end

      def upload_html_to_png
        content = params[:content]
        begin
          uri = URI("#{ENV['EXAMHERO_URL']}/tools/html_to_png")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Accept' => 'application/json')
          request.body = {
            html_content: content
          }.to_json
          http.read_timeout = 600_000

          response = http.request(request)
          res = JSON.parse(response.body)

          if res['screenshot'].present?
            img = Base64.strict_decode64(res['screenshot'])
            screenshot = Magick::ImageList.new.from_blob(img)
            file_url = AzureService.uploadBlob(screenshot.to_blob, 'chatting_report.png', 'image/png')
            render json: { success: true, file_url: }, status: :ok
          else
            render json: { success: false, error: 'Something went wrong' }, status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
