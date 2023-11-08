# frozen_string_literal: true

module Api
  module V1
    class ChatbotsController < ApiController
      before_action :authenticate_user!, only: %i[create update destroy mark_messages_read]
      before_action :current_user_chatbots, only: %i[index]

      def index
        @chatbots = Chatbot.all.order(created_at: :desc)
        @chatbots = Kaminari.paginate_array(@chatbots).page(params[:page])
        @chatbots_with_folders = @chatbots.map do |chatbot|
          if chatbot.source['folder_id'].present?
            folders = Folder.find(chatbot.source['folder_id']) if chatbot.source['folder_id'][0].present?
            { chatbot:, folders: }
          elsif chatbot.source['document_id'].present?
            documents = Document.find(chatbot.source['document_id'])
            { chatbot:, documents: }
          end
        end
        render json: { success: true, chatbots: @chatbots_with_folders, meta: pagination_meta(@chatbots) }, status: :ok
      end

      def show
        @chatbot = Chatbot.find(params[:id])
        @chatbot.increment_access_count!

        if @chatbot.source['folder_id'].present?
          @folders = Folder.find(@chatbot.source['folder_id']) if @chatbot.source['folder_id'][0].present?
          render json: { success: true, chatbot: @chatbot, folders: @folders }, status: :ok
        elsif @chatbot.source['document_id'].present?
          @documents = Document.find(@chatbot.source['document_id'])
          render json: { success: true, chatbot: @chatbot, documents: @documents }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
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
        @chatbot.user = current_user

        if params['source']['folder_id'].present?
          @folders = Folder.find(params['source']['folder_id'])
          @chatbot.source['folder_id'] = @folders.pluck(:id)
        elsif params['source']['document_id'].present?
          @documents = Document.find(params['source']['document_id'])
          @chatbot.source['document_id'] = @documents.pluck(:id)
        end

        @chatbot.meta['chain_features'] = params[:chain_features]

        if @chatbot.save
          render json: { success: true, chatbot: @chatbot }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        @chatbot = Chatbot.find(params[:id])
        @chatbot.meta['chain_features'] = params[:chain_features]
        if params['source']['folder_id'].present?
          @folders = Folder.find(params['source']['folder_id'])
          @chatbot.source['folder_id'] = @folders.pluck(:id)
        elsif params['source']['document_id'].present?
          @documents = Document.find(params['source']['document_id'])
          @chatbot.source['document_id'] = @documents.pluck(:id)
        end
        if @chatbot.update(chatbot_params)
          render json: { success: true, chatbot: @chatbot }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @chatbot = Chatbot.find(params[:id])
        if @chatbot.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def assistantQA
        @chatbot = Chatbot.find(params[:id])
        @documents = []
        if @chatbot
          if @chatbot.source['folder_id'].present?
            @folders = @chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
            @folders.each do |folder|
              @documents.concat(folder.documents)
            end
          elsif @chatbot.source['document_id'].present?
            @docs = Document.find(@chatbot.source['document_id'])
            @documents.concat(@docs)
          end
          @metadata = {
            document_id: @documents.map(&:id)
          }
          puts @documents.length
          @qaRes = AiService.assistantQA(params[:query], params[:chat_history], getSubdomain, @metadata)
          puts @qaRes
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
          if @chatbot.source['folder_id'].present?
            @folders = @chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
            @folders.each do |folder|
              @documents.concat(folder.documents)
            end
          elsif @chatbot.source['document_id'].present?
            @docs = Document.find(@chatbot.source['document_id'])
            @documents.concat(@docs)
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

      private

      def chatbot_params
        params.require(:chatbot).permit(:name, :description, :meta, :source, :category, :is_public, :expired_at)
      end

      def current_user_chatbots
        @current_user_chatbots = current_user.chatbots.order(created_at: :desc)
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
    end
  end
end
