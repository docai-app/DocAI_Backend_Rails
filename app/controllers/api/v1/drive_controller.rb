class Api::V1::DriveController < ApiController
  before_action :authenticate_user!, only: [:index, :show, :share]

  def index
    @folders = Folder.where(parent_id: nil)
    @documents = Document.where(folder_id: nil).as_json(except: [:label_list])
    render json: { success: true, folders: @folders, documents: @documents }, status: :ok
  end

  def show
    @folder = Folder.where(parent_id: params[:id])
    @ancestors = Folder.find_by(id: params[:id]).ancestors
    if current_user.has_role? :r, Folder.find(params[:id])
      @documents = Document.where(folder_id: params[:id]).as_json(except: [:label_list])
      render json: { success: true, folders: @folder, documents: @documents, ancestors: @ancestors }, status: :ok
    else
      render json: { success: false, error: "You don't have permission to access this folder" }, status: :ok
    end
  end

  def share
    @folder = Folder.find(params[:id])
    @user = User.find_by(email: params[:user_email])
    @folder.share_with(@user)
    render json: { success: true, folder: @folder }, status: :ok
  end
end
