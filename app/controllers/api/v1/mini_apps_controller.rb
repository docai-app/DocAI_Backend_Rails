class Api::V1::MiniAppsController < ApiController
  before_action :authenticate_user!, only: %i[index show create update destroy]
  before_action :current_user_mini_apps, only: %i[index]

  def index
    @mini_apps = @current_user_mini_apps.includes(:folder).as_json(include: :folder)
    @mini_apps = Kaminari.paginate_array(@mini_apps).page(params[:page])
    render json: { success: true, mini_apps: @mini_apps, meta: pagination_meta(@mini_apps) }, status: :ok
  end

  def show
    @mini_app = MiniApp.find(params[:id])
    render json: { success: true, mini_app: @mini_app }, status: :ok
  end

  def create
    @mini_app = MiniApp.new(mini_app_params)
    puts params.inspect
    @mini_app.document_label_list = params[:document_label_list]
    @mini_app.app_function_list = params[:app_function_list]
    @mini_app.meta = params[:meta] if params[:meta]
    @mini_app.user = current_user
    if @mini_app.save
      render json: { success: true, mini_app: @mini_app }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def update
    @mini_app = MiniApp.find(params[:id])
    @mini_app.document_label_list = params[:document_label_list] if params[:document_label_list]
    @mini_app.app_function_list = params[:app_function_list] if params[:app_function_list]
    @mini_app.meta = params[:meta] if params[:meta]
    if @mini_app.update(mini_app_params)
      render json: { success: true, mini_app: @mini_app }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def destroy
    @mini_app = MiniApp.find(params[:id])
    if @mini_app.destroy
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def mini_app_params
    params.require(:mini_app).permit(:name, :description, :meta, :folder_id, :document_label_list, :app_function_list)
  end

  def current_user_mini_apps
    @current_user_mini_apps = current_user.mini_apps.order(created_at: :desc)
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
end
