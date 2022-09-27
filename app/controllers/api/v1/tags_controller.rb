class Api::V1::TagsController < ApiController
  # Show all tags
  def index
    @tags = ActsAsTaggableOn::Tag.all
    render json: { success: true, tags: @tags }, status: :ok
  end

  # Show tag by id
  def show
    @tag = ActsAsTaggableOn::Tag.find(params[:id])
    render json: { success: true, tag: @tag }, status: :ok
  end

  # Show the distinct tags which is tagged by document
  def show_by_tagging
    @tags = ActsAsTaggableOn::Tagging.distinct.pluck(:tag_id).map { |id| ActsAsTaggableOn::Tag.find(id) }
    render json: { success: true, tags: @tags }, status: :ok
  end

  # Create tag
  def create
    @tag = ActsAsTaggableOn::Tag.new(tag_params)
    if @tag.save
      render json: { success: true, tag: @tag }, status: :ok
    else
      render json: { success: false, errors: @tag.errors }, status: :ok
    end
  end

  # Update tag
  def update
    @tag = ActsAsTaggableOn::Tag.find(params[:id])
    if @tag.update(tag_params)
      render json: { success: true, tag: @tag }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def tag_params
    params.require(:tag).permit(:name, :is_checked)
  end
end
