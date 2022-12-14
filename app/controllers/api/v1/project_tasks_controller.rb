class Api::V1::ProjectTasksController < ApiController
  before_action :authenticate_user!, only: [:create, :update, :destroy]

  def index
    @project_tasks = ProjectTask.all.page params[:page]
    render json: { success: true, project_tasks: @project_tasks, meta: pagination_meta(@project_tasks) }, status: :ok
  end

  def show
    @project_task = ProjectTask.find(params[:id])
    render json: { success: true, project_task: @project_task }, status: :ok
  end

  def create
    @project_task = ProjectTask.new(project_task_params)
    @project_task.user_id = current_user.id
    if @project_task.save
      render json: { success: true, project_task: @project_task }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def update
    @project_task = ProjectTask.find(params[:id])
    if @project_task.update(project_task_params)
      render json: { success: true, project_task: @project_task }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def destroy
    @project_task = ProjectTask.find(params[:id])
    if @project_task.destroy
      render json: { success: true }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def project_task_params
    params.require(:project_task).permit(:title, :description, :project_id, :is_completed, :order, :deadline_at)
  end

  def pagination_meta(object) {
    current_page: object.current_page,
    next_page: object.next_page,
    prev_page: object.prev_page,
    total_pages: object.total_pages,
    total_count: object.total_count,
  }   end
end
