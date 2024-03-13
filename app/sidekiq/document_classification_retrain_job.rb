# frozen_string_literal: true

class DocumentClassificationRetrainJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: "document_classification_retrain",
                  throttle: { threshold: 1, period: 10.seconds }

  sidekiq_retry_in { |count| 1.hour * count }

  sidekiq_retries_exhausted do |msg|
    puts "Job retries exhausted: #{msg["error_message"]}"
  end

  def perform(tenant)
    puts "====== DocumentClassificationJob ======"
    puts "====== Tenant: #{tenant} ======"
    Apartment::Tenant.switch!(tenant)
    puts "====== Switch to Tenant: #{tenant} ======"
    documents_to_classify = fetch_documents_to_classify
    if documents_to_classify.count > 20
      view_name = create_classification_view(tenant, Time.now.to_i)
      if train_model(tenant, view_name) && predict_first_document(tenant, view_name, documents_to_classify)
        update_documents_as_trained(documents_to_classify, tenant, view_name)
        puts "====== Documents were successfully processed for classification ======"
      else
        puts "====== Classification failed ======"
      end
    else
      puts "====== No document needs classification ======"
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
    log_error(e.message)
  end

  private

  def fetch_documents_to_classify
    # @documents = Document.classifiable.not_classified_as_document.to_train.retry_limit.order(created_at: :desc)
    @documents = Document.where(is_classified: true).where.not(content: nil).where.not(content: "").where("LENGTH(content) > ?", 10).where(is_document: true).where(is_classifier_trained: false).where(
      "retry_count < ?", 3
    ).order('created_at': :desc)
    puts "====== Documents found: #{@documents.count} ======"
    @documents
  end

  def create_classification_view(tenant, timestamp)
    sql = <<-SQL
      CREATE VIEW public."document_classification_model_#{timestamp}" AS#{" "}
      SELECT documents.id, documents.content, tag_id#{" "}
      FROM "#{tenant}".documents#{" "}
      INNER JOIN "#{tenant}".taggings ON "#{tenant}".documents.id = "#{tenant}".taggings.taggable_id#{" "}
      WHERE "#{tenant}".documents.is_classified = true#{" "}
      AND "#{tenant}".documents.retry_count < 3;
    SQL

    puts "SQL for view creation: #{sql}"
    ActiveRecord::Base.connection.execute(sql)
    "document_classification_model_#{timestamp}"
  end

  def train_model(tenant, view_name)
    res = RestClient::Request.execute(
      method: :post,
      url: "#{ENV["DOCAI_ALPHA_URL"]}/classification/retrain",
      payload: { model: tenant, viewName: view_name }.to_json,
      headers: { content_type: :json, accept: :json },
      timeout: 6000,
    )
    JSON.parse(res)["status"] == "success"
  end

  def predict_first_document(tenant, view_name, documents)
    document_content = documents.where("LENGTH(content) > ?", 100).first.content.to_s
    predict_res = RestClient.get("#{ENV["DOCAI_ALPHA_URL"]}/classification/predict",
                                 params: { content: URI.encode_www_form_component(document_content.truncate(100)),
                                           model: "#{tenant}_#{view_name}" })
    puts "Predict response: #{predict_res}"
    JSON.parse(predict_res)["status"] == "success"
  end

  def update_documents_as_trained(documents, tenant, view_name)
    ClassificationModelVersion.create!(classification_model_name: "#{tenant}_#{view_name}", entity_name: tenant,
                                       description: "Document classification model: #{tenant}_#{view_name}", pervious_version_id: ClassificationModelVersion.where(entity_name: tenant).order(created_at: :desc).first&.id)
    documents.update_all(is_classifier_trained: true)
  end

  def log_error(message)
    puts "====== Error during document classification job: #{message} ======"
  end
end
