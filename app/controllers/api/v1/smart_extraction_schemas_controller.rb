# frozen_string_literal: true

module Api
  module V1
    class SmartExtractionSchemasController < ApiController
      before_action :authenticate_user!

      def index
        @smart_extraction_schemas = SmartExtractionSchema.order(created_at: :desc).page(params[:page])
        render json: { success: true, smart_extraction_schemas: @smart_extraction_schemas, meta: pagination_meta(@smart_extraction_schemas) },
               status: :ok
      end

      def show
        @smart_extraction_schema = SmartExtractionSchema.find(params[:id])
        render json: { success: true, smart_extraction_schema: @smart_extraction_schema }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'SmartExtractionSchema not found' }, status: :not_found
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_document_extracted_data
        @smart_extraction_schema = SmartExtractionSchema.find(params[:id])
        @document_smart_extraction_datum = @smart_extraction_schema.document_smart_extraction_datum
                                                                   .where(status: 'completed')
                                                                   .order(updated_at: :asc)
                                                                   .includes([:document])
                                                                   .as_json(include: { document: { only: %i[id name
                                                                                                            storage_url] } })
        @document_smart_extraction_datum = Kaminari.paginate_array(@document_smart_extraction_datum)
                                                   .page(params[:page])
        render json: {
          success: true,
          document_smart_extraction_datum: @document_smart_extraction_datum,
          meta: pagination_meta(@document_smart_extraction_datum)
        }, status: :ok
      end

      def show_by_label_id
        @smart_extraction_schema = SmartExtractionSchema.where(label_id: params[:label_id]).order(created_at: :desc).page(params[:page])
        render json: { success: true, smart_extraction_schema: @smart_extraction_schema, meta: pagination_meta(@smart_extraction_schema) },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'SmartExtractionSchema not found' }, status: :not_found
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        unless ActsAsTaggableOn::Tag.exists?(params[:label_id])
          return render json: { success: false, error: 'Invalid label_id' },
                        status: :unprocessable_entity
        end

        schema = SmartExtractionSchema.new(smart_extraction_schema_params)
        schema.user = current_user
        schema.has_label = true
        schema.data_schema = params[:data_schema]

        if schema.save
          tag = ActsAsTaggableOn::Tag.find(params[:label_id])
          documents = Document.tagged_with(tag).order(created_at: :desc).as_json(except: [:label_list])

          documents.each do |document|
            DocumentSmartExtractionDatum.create(document_id: document['id'],
                                                smart_extraction_schema_id: schema.id,
                                                data: schema.data_schema)
          end

          create_smart_extraction_schema_view(schema)

          render json: { success: true, smart_extraction_schema: schema }, status: :ok
        else
          render json: { success: false, error: schema.errors.messages }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      def create_by_documents
        document_ids = params[:document_ids] || []
        schema = SmartExtractionSchema.new(smart_extraction_schema_params)
        schema.user = current_user
        schema.data_schema = params[:data_schema]

        if schema.save
          documents = Document.find(document_ids)
          documents.each do |document|
            DocumentSmartExtractionDatum.create(document_id: document.id,
                                                smart_extraction_schema_id: schema.id,
                                                data: schema.data_schema)
          end

          create_smart_extraction_schema_view(schema)

          render json: { success: true, smart_extraction_schema: schema }, status: :ok
        else
          render json: { success: false, error: schema.errors.messages }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      def update
        @smart_extraction_schema = SmartExtractionSchema.find(params[:id])
        @smart_extraction_schema.update(smart_extraction_schema_params)

        if params[:data_schema] && JSON.generate(@smart_extraction_schema.data_schema.to_json) != JSON.generate(params[:data_schema].to_json)
          @smart_extraction_schema.data_schema = params[:data_schema]
          @smart_extraction_schema.save!
          update_document_smart_extraction_datum
          drop_and_create_smart_extraction_schema_views
        elsif params[:data_schema] && JSON.generate(@smart_extraction_schema.data_schema.to_json) == JSON.generate(params[:data_schema].to_json)
          return render json: { success: false, message: 'Data schema is already up to date.' },
                        status: :unprocessable_entity
        end

        render json: { success: true, smart_extraction_schema: @smart_extraction_schema }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      def destroy
        @smart_extraction_schema = SmartExtractionSchema.find(params[:id])
        if @smart_extraction_schema.destroy
          render json: { success: true }, status: :ok
        else
          render json: { success: false }, status: :unprocessable_entity
        end
      end

      def generate_chart
        query = params[:query] || ''
        @smart_extraction_schema = SmartExtractionSchema.find(params[:smart_extraction_schema_id])
        puts "SmartExtractionSchema: #{@smart_extraction_schema.id}"
        chartRes = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/generate/smart_extraction/chart", {
          query:,
          views_name: "smart_extraction_schema_#{@smart_extraction_schema.id}",
          tenant: getSubdomain,
          data_schema: @smart_extraction_schema.data_schema
        }.to_json, { content_type: :json, accept: :json, timeout: 1200 })
        chartRes = JSON.parse(chartRes)
        if chartRes['status'] == true
          html_code = chartRes['result'].match(%r{<html>(.|\n)*?</html>})
          render json: { success: true, chart: html_code.to_s }, status: :ok
        else
          html_code = 'Please reduce the number of form data selected.'
          render json: { success: false, chart: html_code.to_s }, status: :ok
        end
      end

      private

      def smart_extraction_schema_params
        params.require(:smart_extraction_schema).permit(:name, :description, :label_id, :data_schema, :user_id,
                                                        schema: %i[key data_type query])
      end

      def create_smart_extraction_schema_view(schema)
        selectString = schema.data_schema.map { |row| "data->>'#{row[0]}' AS #{row[0]}" }.join(', ')
        sql = "CREATE VIEW \"#{getSubdomain}\".\"smart_extraction_schema_#{schema.id}\" AS SELECT #{selectString}, meta->>'document_uploaded_at' AS uploaded_at FROM \"#{getSubdomain}\".document_smart_extraction_data WHERE smart_extraction_schema_id = '#{schema.id}';"
        ActiveRecord::Base.connection.execute(sql)
        true
      rescue StandardError => e
        puts e.message
        false
      end

      def drop_smart_extraction_schema_view(schema)
        sql = "DROP VIEW IF EXISTS \"#{getSubdomain}\".\"smart_extraction_schema_#{schema.id}\";"
        ActiveRecord::Base.connection.execute(sql)
        true
      rescue StandardError => e
        puts e.message
        false
      end

      def drop_and_create_smart_extraction_schema_views
        drop_smart_extraction_schema_view(@smart_extraction_schema)
        create_smart_extraction_schema_view(@smart_extraction_schema)
      end

      def update_document_smart_extraction_datum
        DocumentSmartExtractionDatum.where(smart_extraction_schema_id: @smart_extraction_schema.id)
                                    .update_all(data: @smart_extraction_schema.data_schema, status: :awaiting,
                                                is_ready: false, retry_count: 0)
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

      def getSubdomain
        Utils.extractRequestTenantByToken(request)
      end
    end
  end
end
