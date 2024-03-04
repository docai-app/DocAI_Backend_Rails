# frozen_string_literal: true

module Api
  module V1
    class ChatbotsController < ApiController
      include Authenticatable

      before_action :authenticate,
                    only: %i[show create update destroy mark_messages_read general_user_chat_with_bot
                             fetch_general_user_chat_history]
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

        @chatbot_config = {}
        assistant = @chatbot.assistant
        @chatbot_config['assistant'] = assistant.try(:name)

        # binding.pry

        experts = @chatbot.experts
        @chatbot_config['experts'] = experts.pluck(:name).uniq
        # binding.pry

        # 要拎用到的工具出黎
        tool_config = chatbot_tools_config(@chatbot)

        agent_tools = {}
        experts.each do |expert|
          expert.agent_tools.each do |at|
            next unless at.meta['initialize'].present?

            agent_tools[at.name] = {
              'initialize': {
                'metadata': at.meta['initialize']['metadata'].transform_keys(&:to_sym).merge(tool_config)
              }
            }
          end
        end

        if assistant.present?
          assistant.agent_tools.each do |at|
            next unless at.meta['initialize'].present?

            agent_tools[at.name] = {
              'initialize': {
                'metadata': at.meta['initialize']['metadata'].transform_keys(&:to_sym).merge(tool_config)
              }
            }
          end
        end

        @chatbot_config['agent_tools'] = agent_tools

        render json: { success: true, chatbot: @chatbot, folders: @folders, chatbot_config: @chatbot_config },
               status: :ok
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
        @chatbot.meta['chain_features'] = params[:chain_features] if params[:chain_features].present?
        @chatbot.meta['assistant'] = params[:assistant] if params[:assistant].present?
        @chatbot.meta['experts'] = params[:experts]
        @chatbot.meta['length'] = params[:length] if params[:length].present?
        @chatbot.energy_cost = params[:energy_cost] if params[:is_public].present? && params[:is_public] == 'true'
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
        @chatbot.meta['chain_features'] = params[:chain_features]
        @chatbot.meta['assistant'] = params[:assistant]
        @chatbot.meta['experts'] = params[:experts]
        @chatbot.meta['length'] = params[:length] if params[:length].present?
        @chatbot.source['folder_id'] = @folders.pluck(:id) if @folders.present?
        if @chatbot.update(chatbot_params)
          @metadata = chatbot_documents_metadata(@chatbot)
          UpdateChatbotAssistiveQuestionsJob.perform_async(@chatbot.id, @metadata, getSubdomain)
          render json: { success: true, chatbot: @chatbot }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update_assistive_questions
        @chatbot = Chatbot.find(params[:id])
        @chatbot.assistive_questions = params[:assistive_questions]
        if @chatbot.save
          render json: { success: true, chatbot: @chatbot }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
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
            tone: @chatbot.meta['tone'] || '專業',
            length: @chatbot.meta['length'] || 'normal'
          }
          LogMessage.create!(
            chatbot_id: @chatbot.id,
            content: params[:query],
            has_chat_history: params[:chat_history].present? && !params[:chat_history].empty?,
            session_id: session.id,
            role: 'user',
            meta: {
              chat_history: params[:chat_history]
            }
          )
          @qaRes = AiService.assistantQA(params[:query], params[:chat_history], getSubdomain, @metadata)
          LogMessage.create!(
            chatbot_id: @chatbot.id,
            content: @qaRes['content'],
            has_chat_history: true,
            session_id: session.id,
            role: 'system',
            meta: {
              chat_history: params[:chat_history]
            }
          )
          render json: { success: true, message: @qaRes }, status: :ok
        else
          render json: { success: false, error: 'Chatbot not found' }, status: :not_found
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # 韮菜用戶 chat with bot (autogen)
      # 同 general_user_chat_with_bot 的不同之處係，只需要記錄聊天結果同扣除能量值
      def general_user_chat_with_bot_via_autogen
        # 先驗證用戶
        authenticate

        @general_user = current_general_user || current_user
        @chatbot = Chatbot.find(params[:chatbot_id])

        # 呢道仲要判斷類型
        # general_user_talk ?
        # quiz ?

        message = @chatbot.messages.create!(
          user: @general_user,
          chatbot_id: @chatbot.id,
          object_type: 'general_user_talk',
          content: params[:message]['content'],
          is_read: true,
          role: params[:sender]
        )

        render json: { success: true, message: }, status: :ok
      end

      # 韮菜用戶 chat with bot (no autogen)
      def general_user_chat_with_bot
        @user_marketplace_item = UserMarketplaceItem.find(params[:id])
        @marketplace_item = @user_marketplace_item.marketplace_item
        puts "UserMarketplaceItem: #{@user_marketplace_item.inspect}"
        puts "MarketplaceItem: #{@marketplace_item.inspect}"
        Apartment::Tenant.switch!(@marketplace_item.entity_name)
        @chatbot = Chatbot.find(@marketplace_item.chatbot_id)
        @general_user = current_general_user
        @documents = []

        if @general_user.check_can_consume_energy(@chatbot, @chatbot.energy_cost)
          @folders = @chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
          @folders.each do |folder|
            @documents.concat(folder.documents)
          end
          @metadata = {
            document_id: @documents.map(&:id),
            language: @chatbot.meta['language'] || '繁體中文',
            tone: @chatbot.meta['tone'] || '專業',
            length: @chatbot.meta['length'] || 'normal'
          }
          @user_marketplace_item.save_message(@general_user, 'user', 'general_user_talk', params[:query], {
                                                belongs_user_id: current_general_user.id
                                              })
          LogMessage.create!(
            chatbot_id: @chatbot.id,
            content: params[:query],
            has_chat_history: params[:chat_history].present? && !params[:chat_history].empty?,
            session_id: session.id,
            role: 'user',
            meta: {
              chat_history: params[:chat_history]
            }
          )
          @qaRes = AiService.assistantQA(params[:query], params[:chat_history], getSubdomain, @metadata)
          @user_marketplace_item.save_message(@general_user, 'system', 'general_user_talk', @qaRes['content'], {
                                                belongs_user_id: current_general_user.id
                                              })
          LogMessage.create!(
            chatbot_id: @chatbot.id,
            content: @qaRes['content'],
            has_chat_history: true,
            session_id: session.id,
            role: 'system',
            meta: {
              chat_history: params[:chat_history]
            }
          )
          puts "General User: #{@general_user.inspect}"
          @general_user.consume_energy(@marketplace_item.id, @chatbot.energy_cost)
          render json: { success: true, message: @qaRes }, status: :ok
        else
          render json: { success: false, error: 'Energy not sufficient for this operation.' }, status: :forbidden
        end
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'Chatbot not found' }, status: :not_found
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

      def fetch_general_user_chat_history
        @user_marketplace_item = UserMarketplaceItem.find(params[:id])
        @marketplace_item = @user_marketplace_item.marketplace_item
        Apartment::Tenant.switch!(@marketplace_item.entity_name)
        @general_user = current_general_user

        @messages = @user_marketplace_item.get_chatbot_messages(current_general_user.id)
        @messages = Kaminari.paginate_array(@messages).page(params[:page])
        render json: { success: true, messages: @messages, meta: pagination_meta(@messages) }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def tool_metadata
        @chatbot = Chatbot.find(params[:id])
        @documents = []
        if @chatbot
          data = chatbot_tools_config(@chatbot)

          render json: { success: true, result: data }, status: :ok
        else
          render json: { success: false, error: 'Chatbot not found' }, status: :not_found
        end
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

      def chatbot_tools_config(chatbot)
        documents = []
        folders = chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
        folders.each do |folder|
          documents.concat(folder.documents)
        end
        metadata = {
          document_ids: documents.map(&:id)
        }

        document_ids = Document.where(id: metadata[:document_ids]).pluck(:id)

        ses_ids = DocumentSmartExtractionDatum.where(document_id: document_ids).pluck(:smart_extraction_schema_id)
        smart_extraction_schemas = SmartExtractionSchema.where(id: ses_ids)

        {
          schema: getSubdomain,
          metadata:,
          smart_extraction_schemas: smart_extraction_schemas.pluck(:name, :id).to_h
        }
      end
    end
  end
end
