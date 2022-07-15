class Api::V1::FormDatumController < ApplicationController
  def index
    @form_datum = FormDatum.all
    render json: { success: true, form_datum: @form_datum }, status: :ok
  end

  def show
    @form_data = FormDatum.find(params[:id])
    render json: { success: true, form_data: @form_data }, status: :ok
  end

  # Show form data by form schema name and date
  def show_by_form_name_and_date
    @form_datum = FormDatum.by_day(params[:date]).where(form_schema: FormSchema.find_by(name: params[:name])).includes([:form_schema, :document]).as_json(include: [:document, :form_schema])
    render json: { success: true, form_datum: @form_datum }, status: :ok
  end

  # Show form data by date
  def show_by_date
    @form_datum = FormDatum.by_day(params[:date]).as_json(include: [:document, :form_schema])
    render json: { success: true, form_datum: @form_datum }, status: :ok
  end

  def create
    @form_data = FormDatum.new(form_data_params)
    if @form_data.save
      render json: { success: true, form_data: @form_data }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  def update
    @form_data = FormDatum.find(params[:id])
    if @form_data.update(form_data_params)
      render json: { success: true, form_data: @form_data }, status: :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private
  def form_data_params
    params.require(:form_datum).permit(:data => {})
  end
end
