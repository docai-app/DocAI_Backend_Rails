# frozen_string_literal: true

module Api
  module Schema
    module V1
      class ChatbotsController < ApiSchemaNoauthController
        def index
          # @chatbots = @current_user_chatbots
          @chatbots = Chatbot.all.order(created_at: :desc)
          @chatbots = Kaminari.paginate_array(@chatbots).page(params[:page])
          @chatbots_with_folders = @chatbots.map do |chatbot|
            folders = Folder.find(chatbot.source['folder_id'])
            { chatbot:, folders: }
          end
          render json: { success: true, chatbots: @chatbots_with_folders, meta: pagination_meta(@chatbots) },
                 status: :ok
        end

        def show
          @chatbot = Chatbot.find(params[:id])
          @folders = Folder.find(@chatbot.source['folder_id'])
          render json: { success: true, chatbot: @chatbot, folders: @folders }, status: :ok
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

        private

        def chatbot_params
          params.require(:chatbot).permit(:name, :description, :meta, :source, :category)
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
end
