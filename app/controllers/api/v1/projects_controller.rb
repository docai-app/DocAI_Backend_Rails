class Api::V1::ProjectsController < ApiController
  before_action :authenticate_user!, only: [:create, :update, :destroy]
  before_action :current_user_project, only: [:update, :destroy]

  def index
    @projects = Project.all.includes([:project_tasks, :user, :folder]).as_json(include: [:project_tasks, :user, :folder])
    @projects = Kaminari.paginate_array(@projects).page(params[:page])
    render json: { success: true, projects: @projects, meta: pagination_meta(@projects) }, status: :ok
  end

  def show
    @project = Project.find(params[:id]).as_json(include: [:project_tasks, :user, :folder])
    render json: { success: true, project: @project }, status: :ok
  end

  def show_tasks
    @project = Project.find(params[:id])
    @project_tasks = @project.project_tasks
    render json: { success: true, project_tasks: @project_tasks }, status: :ok
  end

  def create
    # Create a new folder for the project
    @folder = Folder.new(name: params[:project][:name], user_id: current_user.id)
    @folder.save
    # Create a new project
    @project = Project.new(name: params[:project][:name], description: params[:project][:description], deadline_at: params[:project][:deadline_at], user_id: current_user.id, folder_id: @folder.id)
    if @project.save
      render json: { success: true, project: @project, folder: @folder }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def update
    @project = Project.find(params[:id])
    if @project.update(project_params)
      render json: { success: true, project: @project }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def destroy
    @project = Project.find(params[:id])
    if @project.destroy
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :user_id, :is_public, :is_finished, :deadline_at)
  end

  def current_user_project
    if current_user.has_role? :w, Project.find(params[:id])
      @current_user_project = Project.where(user_id: current_user.id).or(Project.where(user_id: nil))
    else
      render json: { success: false, error: "You don't have permission to edit this project" }, status: :ok
    end
  end

  def pagination_meta(object) {
    current_page: object.current_page,
    next_page: object.next_page,
    prev_page: object.prev_page,
    total_pages: object.total_pages,
    total_count: object.total_count,
  }   end
end
