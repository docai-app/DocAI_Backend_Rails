# frozen_string_literal: true

module Api
  module V1
    class ChatbotsController < ApiController
      include Authenticatable

      before_action :authenticate, only: %i[show create update destroy mark_messages_read]
      before_action :current_user_chatbots, only: %i[index]

      def index
        @chatbots = current_user.chatbots.all.order(created_at: :desc)
        @chatbots = Kaminari.paginate_array(@chatbots).page(params[:page])
        @chatbots_with_folders = @chatbots.map do |chatbot|
          puts chatbot.inspect
          folders = Folder.find(chatbot.source['folder_id']) if chatbot.source['folder_id'][0].present?
          { chatbot:, folders: }
        end
        render json: { success: true, chatbots: @chatbots_with_folders, meta: pagination_meta(@chatbots) }, status: :ok
      end

      def show
        @chatbot = Chatbot.find(params[:id])
        @chatbot.increment_access_count!
        @folders = Folder.find(@chatbot.source['folder_id']) if @chatbot.source['folder_id'][0].present?
        render json: { success: true, chatbot: @chatbot, folders: @folders }, status: :ok
      end

      def messages
        @chatbot = Chatbot.find(params[:id])
        @messages = @chatbot.messages.where(is_read: false).order(created_at: :desc)
        @messages = Kaminari.paginate_array(@messages).page(params[:page])
        render json: { success: true, messages: @messages, meta: pagination_meta(@messages) }, status: :ok
      end

      def mark_messages_read
        # 只有 assignee 係自己的先會 mark read
        @chatbot = Chatbot.find(params[:id])
        @messages = @chatbot.messages.where(is_read: false).order(created_at: :desc)
        @messages.update(is_read: true) # load 過呢條 api, 就當係全部都 read 了
        @messages = Kaminari.paginate_array(@messages).page(params[:page])
        render json: { success: true }
      end

      def create
        @chatbot = Chatbot.new(chatbot_params)
        @folders = Folder.find(params['source']['folder_id'])
        @chatbot.user = current_user
        @chatbot.source['folder_id'] = @folders.pluck(:id)
        @chatbot.meta['language'] = params[:language] if params[:language].present?
        @chatbot.meta['tone'] = params[:tone] if params[:tone].present?
        @chatbot.meta['chain_features'] = params[:chain_features]
        if @chatbot.save
          @metadata = chatbot_documents_metadata(@chatbot)
          UpdateChatbotAssistiveQuestionsJob.perform_async(@chatbot.id, @metadata, getSubdomain)
          render json: { success: true, chatbot: @chatbot }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @chatbot = Chatbot.find(params[:id])
        @folders = Folder.find(params['source']['folder_id']) if params['source']['folder_id'].present?
        @chatbot.meta['language'] = params[:language] if params[:language].present?
        @chatbot.meta['tone'] = params[:tone] if params[:tone].present?
        @chatbot.meta['chain_features'] = params[:chain_features] if params[:chain_features].present?
        @chatbot.source['folder_id'] = @folders.pluck(:id) if @folders.present?
        if @chatbot.update(chatbot_params)
          @metadata = chatbot_documents_metadata(@chatbot)
          UpdateChatbotAssistiveQuestionsJob.perform_async(@chatbot.id, @metadata, getSubdomain)
          render json: { success: true, chatbot: @chatbot }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @chatbot = Chatbot.where(id: params[:id], user_id: current_user.id).first
        if @chatbot.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false, error: @chatbot.errors }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def assistantQA
        @chatbot = Chatbot.find(params[:id])
        @documents = []
        if @chatbot
          @folders = @chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
          @folders.each do |folder|
            @documents.concat(folder.documents)
          end
          @metadata = {
            document_id: @documents.map(&:id),
            language: @chatbot.meta['language'] || '繁體中文',
            tone: @chatbot.meta['tone'] || '專業'
          }
          puts @documents.length
          LogMessage.create!(
            chatbot_id: @chatbot.id,
            content: params[:query],
            has_chat_history: params[:chat_history].present? && !params[:chat_history].empty?,
            session_id: session.id,
            role: 'user'
          )
          @qaRes = AiService.assistantQA(params[:query], params[:chat_history], getSubdomain, @metadata)
          puts @qaRes
          LogMessage.create!(
            chatbot_id: @chatbot.id,
            content: @qaRes['content'],
            has_chat_history: true,
            session_id:,
            role: 'system'
          )
          render json: { success: true, message: @qaRes }, status: :ok
        else
          render json: { success: false, error: 'Chatbot not found' }, status: :not_found
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def assistantQASuggestion
        @chatbot = Chatbot.find(params[:id])
        @documents = []
        if @chatbot
          @folders = @chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
          @folders.each do |folder|
            @documents.concat(folder.documents)
          end
          @metadata = {
            document_id: @documents.map(&:id)
          }
          @qaRes = AiService.assistantQASuggestion(getSubdomain, @metadata)
          puts @qaRes
          render json: { success: true, suggestion: @qaRes }, status: :ok
        else
          render json: { success: false, error: 'Chatbot not found' }, status: :not_found
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def assistantMultiagent
        @chatbot = Chatbot.find(params[:id])
        @documents = []
        if @chatbot
          @folders = @chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
          @folders.each do |folder|
            @documents.concat(folder.documents)
          end
          @metadata = {
            document_ids: @documents.map(&:id)
          }

          document_ids = Document.where(id: @metadata[:document_ids]).pluck(:id)
          # smart_extraction_schemas = SmartExtractionSchema.distinct.joins(:document_smart_extraction_datum).where(document_smart_extraction_data: { document_id: documents })

          ses_ids = DocumentSmartExtractionDatum.where(document_id: document_ids).pluck(:smart_extraction_schema_id)
          smart_extraction_schemas = SmartExtractionSchema.where(id: ses_ids)

          # binding.pry
          @qaRes = AiService.assistantMultiagent(params[:query], getSubdomain, @metadata, smart_extraction_schemas)
          render json: { success: true, result: @qaRes }, status: :ok
        else
          render json: { success: false, error: 'Chatbot not found' }, status: :not_found
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def shareChatbotWithSignature
        @chatbot = Chatbot.find(params[:id])
        puts current_user
        apiKey = current_user.active_api_key.key
        signature = Utils.encrypt(apiKey) if apiKey.present?
        if @chatbot && apiKey
          render json: { success: true, chatbot: @chatbot, signature: }, status: :ok
        else
          render json: { success: false, error: 'Chatbot not found' }, status: :not_found
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def chatbot_params
        params.require(:chatbot).permit(:name, :description, :meta, :source, :category, :is_public, :expired_at)
      end

      def current_user_chatbots
        @current_user_chatbots = current_user.chatbots.order(created_at: :desc)
      end

      def chatbot_documents_metadata(chatbot)
        @documents = []
        @folders = chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
        puts @folders.inspect
        @folders.each do |folder|
          puts 'Folder document: ', folder.documents
          @documents.concat(folder.documents)
        end
        @metadata = {
          document_id: @documents.map(&:id)
        }
        @metadata
      end

      def pagination_meta(object)
        {
          current_page: object.current_page,
          next_page: object.next_page,
          prev_page: object.prev_page,
          total_pages: object.total_pages,
          total_count: object.total_count
        }
      end

      def getSubdomain
        Utils.extractRequestTenantByToken(request)
      end

      # def authenticate!
      #   api_key = request.headers['X-API-KEY']
      #   if !api_key.present?
      #     authenticate_user!
      #   end
      # end
      # def authenticate_with_api_key(key)
      #   unless ApiKey.active.exists?(key: key)
      #     render json: { success: false, error: 'Invalid API Key' }, status: :unauthorized
      #   end
      # end
    end
  end
end
