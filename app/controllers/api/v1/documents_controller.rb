class Api::V1::DocumentsController < ApiController
  before_action :set_document, only: [:show, :update, :destroy, :approval]

  before_action :authenticate_user!, only: [:approval]
  # before_action :require_admin, only: []

  def index
    @documents = Document.all
  end

  # Show document by id
  def show
    @document = Document.find(params[:id])
    render json: { success: true, document: @document }, status: :ok
  end

  # Show documents by name like name param
  def show_by_name
    @document = Document.includes([:taggings]).where("name like ?", "%#{params[:name]}%").order(:created_at => :desc)
    # Update all the documents' storage_url
    @document.each do |document|
      document.storage_url = document.file.url
    end
    render json: { success: true, documents: @document }, status: :ok
  end

  # Show documents by content like content param
  def show_by_content
    @document = Document.includes([:taggings]).where("content like ?", "%#{params[:content]}%").order(:created_at => :desc)
    # Update all the documents' storage_url
    @document.each do |document|
      document.storage_url = document.file.url
    end
    render json: { success: true, documents: @document }, status: :ok
  end

  # Show documents by ActsAsTaggableOn tag id
  def show_by_tag
    tag = ActsAsTaggableOn::Tag.find(params[:tag_id])
    @document = Document.tagged_with(tag).order(:created_at => :desc).includes([:taggings])
    render json: { success: true, documents: @document }, status: :ok
  end

  def create
    binding.pry
    @document = Document.new(document_params)
    if @document.save
      render :show
    else
      render json: { success: false }, status: :unprocessable_entity
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

  def tags
    @tags = Documents.all_tags
    render json: @tags
  end

  # Show and Predict the Latest Uploaded Document
  def show_latest_predict
    @document = Document.where(status: 0).order(:created_at).last
    res = RestClient.get ENV["DOCAI_ALPHA_URL"] + "/classification/predict?id=" + @document.id.to_s
    render json: { success: true, prediction: { tag: JSON.parse(res)["label"], document: @document } }, status: :ok
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:name, :storage_url, :content, :status, :file)
  end
end
