class Api::V1::DocumentsController < ApiController

  before_action :set_document, only: [:show, :update, :destroy, :approval]

  before_action :authenticate_user!, only: [:approval]


  def index
  end

  def show
    @document = Document.first
  end

  def create
    @document = Document.new(document_params)
    if @document.save
      render :show
    else
      render json: {success: false}, status: :unprocessable_entity
    end
  end

  def destroy
  end

  def update
  end

  def approval
    # binding.pry
    @document.approval_user = current_user
    @document.approval_at = DateTime.current
    @document.approval_status = params["status"]
    if @document.save
      render :show
    else
      json_fail("Document approval failed")
    end
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:name, :storage_url, :content, :status)
  end

end
