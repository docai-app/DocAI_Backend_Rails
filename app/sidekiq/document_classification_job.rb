# frozen_string_literal: true

class DocumentClassificationJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: 'document_classification', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(tenant)
    @documents = Document.where(is_classified: true).where.not(content: nil).where.not(content: '').where('LENGTH(content) > ?', 10).where(is_document: true).where(is_classifier_trained: false).where(
      'retry_count < ?', 3
    ).order('created_at': :desc)
    Apartment::Tenant.switch!(tenant)
    timestamp = Time.now.to_i
    # document = Document.find(document_id)
    # if document.present? && document.is_document && document.content.present? && !document.is_classifier_trained
    #   classificationRes = RestClient.post "#{ENV['DOCAI_ALPHA_URL']}/classification/confirm",
    #                                       { content: document.content, label: label_id, model: subdomain }.to_json, { content_type: :json, accept: :json }
    #   if JSON.parse(classificationRes)['status']
    #     document.is_classified = true
    #     document.is_classifier_trained = true
    #     document.confirmed!
    #   else
    #     document.retry_count += 1
    #     document.error_message = JSON.parse(classificationRes)
    #     document.save!
    #   end
    # end
    if @documents.present? && @documents.count > 5
      sql = "CREATE VIEW public.\"document_classification_model_#{timestamp}\" AS SELECT documents.id, documents.content, tag_id FROM \"#{tenant}\".documents INNER JOIN \"#{tenant}\".taggings ON \"#{tenant}\".documents.id = \"#{tenant}\".taggings.taggable_id WHERE \"#{tenant}\".documents.is_classified = true AND \"#{tenant}\".documents.retry_count < 3;"
      puts "====== sql: #{sql} ======"
      ActiveRecord::Base.connection.execute(sql)
      res = RestClient.post "#{ENV['DOCAI_ALPHA_URL']}/classification/retrain",
                            { model: tenant, viewName: "document_classification_model_#{timestamp}" }.to_json, { content_type: :json, accept: :json }
      puts "====== res: #{res} ======"
      if JSON.parse(res)['status'] == 'Success'
        ClassificationModelVersion.create(
          classification_model_name: "#{tenant}_document_classification_model_#{timestamp}",
          entity_name: tenant,
          pervious_version_id: ClassificationModelVersion.where(entity_name: tenant).order(created_at: :desc).first&.id || nil
        )
        @documents.update_all(is_classifier_trained: true)
      end
      puts '====== perform ====== documents was successfully processed'
    else
      puts '====== perform ====== no document needs classification ======'
    end
  rescue StandardError => e
    # document = Document.find(document_id)
    # document.retry_count += 1
    # document.error_message = e.message
    # document.save!
    # puts "====== error ====== document.id: #{document_id}"
    # puts "Document Classification processing failed for document #{document_id}: #{e.message}"
    puts "====== error ====== error: #{e.message}"
  end
end
