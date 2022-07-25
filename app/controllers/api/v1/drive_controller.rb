class Api::V1::DriveController < ApiController
    def index
        @folders = Folder.where(parent_id: nil)
        @documents = Document.where(folder_id: nil).as_json(except: [:label_list])
        render json: { success: true, folders: @folders, documents: @documents }, status: :ok
    end

    def show
        # @documents = Document.where(folder_id: params[:id]).as_json(except: [:label_list])
        # render json: { success: true, folders: @folder, documents: @documents }, status: :ok
        # @folder = Folder.where(parent_id: params[:id])
        if current_user.has_role? :r, Folder.find(params[:id])
        # puts current_user.has_role? :r, Folder.all.first
            @documents = Document.where(folder_id: params[:id]).as_json(except: [:label_list])
            render json: { success: true, folders: @folder, documents: @documents }, status: :ok
        else
            render json: { success: false, error: "You don't have permission to access this folder" }, status: :ok
        end
    end
end
