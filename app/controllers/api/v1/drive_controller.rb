class Api::V1::DriveController < ApiController
  before_action :authenticate_user!, only: [:index, :show, :share]
  before_action :current_user_folder, only: [:show, :share]

  def index
    @folders = Folder.where(parent_id: nil).includes(:user).as_json(include: { user: { only: [:id, :email, :nickname] } })
    @documents = Document.where(folder_id: nil).includes(:users).as_json(except: [:label_list], include: { users: { only: [:id, :email, :nickname] } })
    render json: { success: true, folders: @folders, documents: @documents }, status: :ok
  end

  def show
    @folder = Folder.where(parent_id: params[:id])
    @ancestors = @current_user_folder.ancestors
    @documents = Document.where(folder_id: params[:id]).as_json(except: [:label_list])
    render json: { success: true, folder: @current_user_folder, folders: @folder, ancestors: @ancestors, documents: @documents }, status: :ok
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
end
