# frozen_string_literal: true

module Api
  module V1
    class FoldersController < ApiController
      before_action :current_user_folder, only: %i[update destroy]
      before_action :authenticate_user!, only: %i[create update destroy]

      def index
        @folders = Folder.all.page params[:page]
        render json: { success: true, folders: @folders, meta: pagination_meta(@folders) }, status: :ok
      end

      def show
        @folder = Folder.find(params[:id])
        @children = @folder.children
        @parent = @folder.parent
        @ancestors = @folder.ancestors
        render json: { success: true, folder: @folder, children: @children, parent: @parent, ancestors: @ancestors },
               status: :ok
      end

      def show_ancestors
        @folder = Folder.find(params[:id])
        @ancestors = @folder.ancestors
        render json: { success: true, ancestors: @ancestors }, status: :ok
      end

      def create
        @folder = Folder.new(folder_params)
        @folder.user = current_user
        if @folder.save
          render json: { success: true, folder: @folder }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def update
        if @current_user_folder.update(folder_params)
          render json: { success: true, folder: @current_user_folder }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def destroy
        @folder = Folder.find_by(id: params[:id], user_id: current_user.id)
        if @folder.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def folder_params
        params.require(:folder).permit(:name, :parent_id)
      end

      def current_user_folder
        if current_user.has_role? :w, Folder.find(params[:id])
          @current_user_folder = Folder.find_by(id: params[:id])
        else
          render json: { success: false, error: "You don't have permission to access this folder" }, status: :ok
        end
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
