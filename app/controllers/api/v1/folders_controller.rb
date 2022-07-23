class Api::V1::FoldersController < ApiController
  before_action :authenticate_user!, only: [:create, :update]

  def index
    @folders = Folder.all.page params[:page]
    render json: { success: true, folders: @folders, meta: pagination_meta(@folders) }, status: :ok
  end

  def show
    @folder = Folder.find(params[:id])
    render json: { success: true, folder: @folder }, status: :ok
  end

  def create
    @folder = Folder.new(folder_params)
    if @folder.save
      render json: { success: true, folder: @folder }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def update
    @folder = Folder.find(params[:id])
    if @folder.update(folder_params)
      render json: { success: true, folder: @folder }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def folder_params
    params.require(:folder).permit(:name, :parent_id)
  end

  def pagination_meta(object) {
    current_page: object.current_page,
    next_page: object.next_page,
    prev_page: object.prev_page,
    total_pages: object.total_pages,
    total_count: object.total_count,
  }   end
end
