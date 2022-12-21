class Api::V1::DriveController < ApiController
  before_action :authenticate_user!, only: [:index, :show, :share]
  before_action :current_user_folder, only: [:show, :share]

  def index
    @folders = Folder.where(parent_id: nil).includes(:user).as_json(include: { user: { only: [:id, :email, :nickname] } })
    @folders = Kaminari.paginate_array(@folders).page(params[:page]).per(50)
    @documents = Document.where(folder_id: nil).includes(:user).as_json(except: [:label_list], include: { user: { only: [:id, :email, :nickname] } })
    @documents = Kaminari.paginate_array(@documents).page(params[:page]).per(50)
    @meta = compare_pagination_meta(@folders, @documents)
    render json: { success: true, folders: @folders, documents: @documents, meta: @meta }, status: :ok
  end

  def show
    @folders = Folder.where(parent_id: params[:id]).includes(:user).as_json(include: { user: { only: [:id, :email, :nickname] } })
    @folders = Kaminari.paginate_array(@folders).page(params[:page]).per(50)
    @ancestors = @current_user_folder.ancestors
    @documents = Document.where(folder_id: params[:id]).includes(:user).as_json(except: [:label_list], include: { user: { only: [:id, :email, :nickname] } })
    @documents = Kaminari.paginate_array(@documents).page(params[:page]).per(50)
    @meta = compare_pagination_meta(@folders, @documents)
    render json: { success: true, folder: @current_user_folder, folders: @folders, ancestors: @ancestors, documents: @documents, meta: @meta }, status: :ok
  end

  def share
    # @folder = Folder.find(params[:id])
    @user = User.find_by(email: params[:user_email])
    if @user != nil
      @current_user_folder.share_with(@user)
      render json: { success: true, folder: @current_user_folder }, status: :ok
    else
      render json: { success: false, error: "User not found" }, status: :ok
    end
  end

  private

  def current_user_folder
    if current_user.has_role? :w, Folder.find(params[:id])
      @current_user_folder = Folder.find_by(id: params[:id])
    else
      render json: { success: false, error: "You don't have permission to access this folder" }, status: :ok
    end
  end

  def compare_pagination_meta(object1, object2)
    if pagination_meta(object1)[:total_pages] >= pagination_meta(object2)[:total_pages]
      @meta = pagination_meta(object1)
    else
      @meta = pagination_meta(object2)
    end
    return @meta
  end

  def pagination_meta(object)
    {
      current_page: object.current_page,
      next_page: object.next_page,
      prev_page: object.prev_page,
      total_pages: object.total_pages,
      total_count: object.total_count,
    }
  end
end
