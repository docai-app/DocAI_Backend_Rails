class Api::V1::DriveController < ApiController
  before_action :authenticate_user!
  before_action :current_user_folder, only: [:show, :share]
  before_action :can_move_items_to_folder, only: [:move_items]
  before_action :has_rights_to_move_items?, only: [:move_items]

  def index
    @folders = Folder.where(parent_id: nil).order(updated_at: :desc).includes(:user).as_json(include: { user: { only: [:id, :email, :nickname] } })
    @folders = Kaminari.paginate_array(@folders).page(params[:page]).per(50)
    @documents = Document.where(folder_id: nil).order(updated_at: :desc).includes(:user, :labels).as_json(except: [:label_list], include: { user: { only: [:id, :email, :nickname] }, labels: { only: [:id, :name] } })
    @documents = Kaminari.paginate_array(@documents).page(params[:page]).per(50)
    @meta = compare_pagination_meta(@folders, @documents)
    render json: { success: true, folders: @folders, documents: @documents, meta: @meta }, status: :ok
  end

  def show
    @folders = Folder.where(parent_id: params[:id]).order(updated_at: :desc).includes(:user).as_json(include: { user: { only: [:id, :email, :nickname] } })
    @folders = Kaminari.paginate_array(@folders).page(params[:page]).per(50)
    @ancestors = @current_user_folder.ancestors
    @documents = Document.where(folder_id: params[:id]).order(updated_at: :desc).includes([:user, :labels]).as_json(except: [:label_list], include: { user: { only: [:id, :email, :nickname] }, labels: { only: [:id, :name] } })
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

  def move_items
    @target_folder = Folder.find(params[:target_folder_id])
    @folder_items = params[:folder_items] || []
    @document_items = params[:document_items] || []
    @current_folder_id = params[:current_folder_id] || nil

    @folder_items.each do |item|
      @folder = Folder.find_by(id: item, parent_id: params[:current_folder_id]).update(parent_id: @target_folder[:id])
    end

    @document_items.each do |item|
      @document = Document.find_by(id: item, folder_id: params[:current_folder_id]).update(folder_id: @target_folder[:id])
    end

    render json: { success: true }, status: :ok
  end

  private

  def current_user_folder
    if current_user.has_role? :w, Folder.find(params[:id])
      @current_user_folder = Folder.find_by(id: params[:id])
    else
      render json: { success: false, error: "You don't have permission to access this folder" }, status: :ok
    end
  end

  def can_move_items_to_folder
    if current_user.has_role? :w, Folder.find(params[:target_folder_id])
      @can_move_items_to_folder = true
    else
      render json: { success: false, error: "You don't have permission to move to this folder" }, status: :ok
    end
  end

  def has_rights_to_move_items?
    @folder_items = params[:folder_items] || []
    @document_items = params[:document_items] || []

    @folder_items.each do |item|
      if Folder.find_by(id: item, parent_id: params[:current_folder_id]).has_rights_to_write?(current_user)
        next
      else
        render json: { success: false, error: "You don't have permission to move this folder" }, status: :ok
      end
    end

    @document_items.each do |item|
      if Document.find_by(id: item, folder_id: params[:current_folder_id]).has_rights_to_write?(current_user)
        next
      else
        render json: { success: false, error: "You don't have permission to move this document" }, status: :ok
      end
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
