class Api::V1::DagsController < ApiController

  before_action :set_dag, except: [:create]

  def index
    @dags = Dag.all.page params[:page]
    render json: { success: true, dags: @dags, meta: pagination_meta(@dags) }, status: :ok
  end

  def show
  end

  def create
    param = params.permit!.to_h.except("action", "controller", "dag")

    # 先檢查 dag 的名稱，如果已有的話，咁就 update
    @dag = Dag.where(name: Dag.normalize_name(param['name'])).first
    if @dag.nil?
      @dag = Dag.new(user: api_user)
    end
    
    @dag['meta'] = param
    @dag.name = param['name']
    if @dag.save!
      json_success(@dag)
    else
      json_fail
    end
  end

  def update
    param = params.permit!.to_h.except("action", "controller", "dag")
    @dag['meta'] = param
    @dag.name = param['name']
    if @dag.save!
      json_success(@dag)
    else
      json_fail
    end
  end

  def destroy
    @dag.destroy!
    json_success
  end

  protected

  def set_dag
    param = params.permit!.to_h.except("action", "controller", "dag")
    @dag = Dag.where(name: param['dag_name']).first
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