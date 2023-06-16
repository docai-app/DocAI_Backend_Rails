# frozen_string_literal: true

module Api
  module V1
    class FormDatumController < ApiController
      before_action :authenticate_user!, only: %i[create update destroy]

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
        @form_datum = FormDatum.by_day(params[:date]).where(form_schema: FormSchema.find_by(name: params[:name])).includes(%i[
                                                                                                                             form_schema document
                                                                                                                           ]).as_json(include: %i[
                                                                                                                                        document form_schema
                                                                                                                                      ])
        render json: { success: true, form_datum: @form_datum }, status: :ok
      end

      # Show form data by date
      def show_by_date
        @form_datum = FormDatum.by_day(params[:date]).as_json(include: %i[document form_schema])
        render json: { success: true, form_datum: @form_datum }, status: :ok
      end

      # Show form data by filter params and form schema id
      def show_by_filter_and_form_schema_id
        @form_datum = FormDatum.where(form_schema_id: params[:form_schema_id]).where('data @> ?',
                                                                                     params[:filter].to_json).order(created_at: :desc).includes(%i[form_schema
                                                                                                                                                   document]).as_json(include: {
                                                                                                                                                                        document: { except: [:label_list] }, form_schema: {}
                                                                                                                                                                      })
        @form_datum = Kaminari.paginate_array(@form_datum).page(params[:page])
        render json: { success: true, form_datum: @form_datum, meta: pagination_meta(@form_datum) }, status: :ok
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

      def destroy
        @form_data = FormDatum.find(params[:id])
        if @form_data.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      private

      def form_data_params
        params.require(:form_datum).permit(data: {})
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
