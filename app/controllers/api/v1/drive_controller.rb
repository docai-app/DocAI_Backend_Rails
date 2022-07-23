class Api::V1::DriveController < ApiController
    def index
        @folders = Folder.where(parent_id: nil)
        @documents = Document.where(folder_id: nil).as_json(except: [:label_list])
        render json: { success: true, folders: @folders, documents: @documents }, status: :ok
    end
end
