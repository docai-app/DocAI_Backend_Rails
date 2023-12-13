# frozen_string_literal: true

module Api
  module V1
    class DriveController < ApiController
      include ActionController::Live # Ensure this line is there

      before_action :authenticate_user!
      before_action :current_user_folder, only: %i[show share]
      before_action :can_move_items_to_folder, only: [:move_items]
      before_action :has_rights_to_move_items?, only: [:move_items]

      def index
        @folders = current_user_accessible_folders
        @folders = Kaminari.paginate_array(@folders).page(params[:page])
        @documents = Document.where(folder_id: nil).select(Document.attribute_names - %w[label_list content]).order(updated_at: :desc).includes(:user, :labels).as_json(
          except: %i[label_list
                     content], include: { user: { only: %i[id email nickname] }, labels: { only: %i[id name] } }
        )
        @documents = Kaminari.paginate_array(@documents).page(params[:page])
        @meta = compare_pagination_meta(@folders, @documents)
        render json: { success: true, folders: @folders, documents: @documents, meta: @meta }, status: :ok
      end

      def show
        @folders = Folder.where(parent_id: params[:id]).order(updated_at: :desc).includes(:user).as_json(include: { user: { only: %i[
                                                                                                           id email nickname
                                                                                                         ] } })
        @folders = Kaminari.paginate_array(@folders).page(params[:page])
        @ancestors = @current_user_folder.ancestors
        @documents = Document.where(folder_id: params[:id]).order(updated_at: :desc).includes(%i[user labels]).as_json(
          except: [:label_list], include: { user: { only: %i[id email nickname] }, labels: { only: %i[id name] } }
        )
        @documents = Kaminari.paginate_array(@documents).page(params[:page])
        @meta = compare_pagination_meta(@folders, @documents)
        render json: { success: true, folder: @current_user_folder, folders: @folders, ancestors: @ancestors, documents: @documents, meta: @meta },
               status: :ok
      end

      def share
        @user = User.find_by(email: params[:user_email])
        if !@user.nil?
          @current_user_folder.share_with(@user)
          render json: { success: true, folder: @current_user_folder }, status: :ok
        else
          render json: { success: false, error: 'User not found' }, status: :ok
        end
      end

      def move_items
        @target_folder = Folder.find(params[:target_folder_id])
        @folder_items = params[:folder_items] || []
        @document_items = params[:document_items] || []
        @current_folder_id = params[:current_folder_id] || nil

        @folder_items.each do |item|
          @folder = Folder.find_by(id: item,
                                   parent_id: params[:current_folder_id]).update(parent_id: @target_folder[:id])
        end

        @document_items.each do |item|
          @document = Document.find_by(id: item,
                                       folder_id: params[:current_folder_id]).update(folder_id: @target_folder[:id])
        end

        render json: { success: true }, status: :ok
      end

      def download_zip
        folder_ids = params[:folder_ids] || []
        document_ids = params[:document_ids] || []

        folders = Folder.where(id: folder_ids)
        documents = Document.where(id: document_ids)

        # Set the appropriate headers for zip file download.
        response.headers['Content-Type'] = 'application/zip'
        response.headers['Content-Disposition'] = 'attachment; filename=documents.zip'
        response.headers['Cache-Control'] = 'no-cache'
        response.headers['Last-Modified'] = Time.now.httpdate.to_s
        response.headers['X-Accel-Buffering'] = 'no'
        response.headers.delete('Content-Length') # Delete this for streaming

        # Use the service object to stream the zip file.
        DocumentsStreamerService.stream(documents:, folders:) do |chunk|
          response.stream.write(chunk)
        end
      ensure
        response.stream.close
      end

      private

      def current_user_folder
        @folder = Folder.find(params[:id])

        if @folder.user.nil? || current_user.has_role?(:w, @folder) || @folder.allow_user_access?(current_user)
          @current_user_folder = @folder
        else
          render json: { success: false, error: "You don't have permission to access this folder" }, status: :ok
        end
      end

      def current_user_accessible_folders
        all_root_folders = Folder.where(parent_id: nil).order(created_at: :desc).includes(:user)

        folder_ids_with_rights = current_user.roles.where(name: 'w', resource_type: 'Folder').pluck(:resource_id)
        label_folders = ActsAsTaggableOn::Tag.for_context(:labels).pluck(:folder_id)

        accessible_folders = all_root_folders.select do |folder|
          folder_ids_with_rights.include?(folder.id) || folder.user == current_user || folder.user.nil? && !label_folders.include?(folder.id)
        end

        accessible_folders.as_json(include: { user: { only: %i[id email nickname] } })
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
          next if Folder.find_by(id: item, parent_id: params[:current_folder_id]).has_rights_to_write?(current_user)

          render json: { success: false, error: "You don't have permission to move this folder" }, status: :ok
          break
        end

        @document_items.each do |item|
          next if Document.find_by(id: item, folder_id: params[:current_folder_id]).has_rights_to_write?(current_user)

          render json: { success: false, error: "You don't have permission to move this document" }, status: :ok
          break
        end
      end

      def compare_pagination_meta(object1, object2)
        @meta = if pagination_meta(object1)[:total_pages] >= pagination_meta(object2)[:total_pages]
                  pagination_meta(object1)
                else
                  pagination_meta(object2)
                end
        @meta
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
  end
end
