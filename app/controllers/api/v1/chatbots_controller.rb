class Api::V1::ChatbotsController < ApplicationController
  before_action :authenticate_user!, only: %i[create update destroy]
  before_action :current_user_chatbots, only: %i[index]

  def index
    @chatbots = @current_user_chatbots
    @chatbots = Kaminari.paginate_array(@chatbots).page(params[:page])
    render json: { success: true, chatbots: @chatbots }, status: :ok
  end

  def show
    @chatbot = Chatbot.find(params[:id])
    render json: { success: true, chatbot: @chatbot }, status: :ok
  end

  def create
    @chatbot = Chatbot.new(chatbot_params)
    puts params
    @chatbot.user = current_user
    @chatbot.source = params[:source]
    if @chatbot.save
      render json: { success: true, chatbot: @chatbot }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def update
    @chatbot = Chatbot.find(params[:id])
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
      @folders = @chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
      @folders.each do |folder|
        @documents.concat(folder.documents)
      end
      @metadata = {
        document_id: @documents.map(&:id)
      }
      puts @documents.length
      @qaRes = AiService.assistantQA(params[:query], getSubdomain, @metadata)
      puts @qaRes
      render json: { success: true, message: @qaRes }, status: :ok
    else
      render json: { success: false, error: 'Chatbot not found' }, status: :not_found
    end
  rescue StandardError => e
    # Handle any other exceptions here
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
    Utils.extractReferrerSubdomain(request.referrer) || 'public'
  end
end
