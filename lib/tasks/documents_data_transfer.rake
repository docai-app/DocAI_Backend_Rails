# frozen_string_literal: true

namespace :documents_data_transfer do
  # Create a task for find all has label_ids.first's documents
  task update_documents_classified_status: :environment do
    puts 'find_documents_with_label_ids'
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      labeledCound = 0
      nonLabeledCount = 0
      labeledDocumentIds = []
      nonLabeledDocumentIds = []
      @documents = Document.includes([:taggings]).order('created_at': :desc).all.as_json(include: [:taggings])

      puts "Number of documents have to check: #{@documents.length}"

      @documents.each do |document|
        if @document['label_list'].first.present?
          labeledCound += 1
          labeledDocumentIds << document['id']
          if (labeledCound % 100).zero?
            puts "Number of documents with label: #{labeledCound}
            "
          end
        elsif @document['label_list'].first.blank?
          nonLabeledCount += 1
          nonLabeledDocumentIds << document['id']
          puts "Number of documents without label: #{nonLabeledCount}" if (nonLabeledCount % 100).zero?
        end
      end
      puts "Number of documents with label: #{labeledCound}"
      puts "Number of documents without label: #{nonLabeledCount}"

      @labeledDocuments = Document.find(labeledDocumentIds)
      @labeledDocuments.each do |labeledDocument|
        labeledDocument.is_classified = true
        labeledDocument.save
      end

      puts 'Finished updating labeled documents'

      @nonLabeledDocuments = Document.find(nonLabeledDocumentIds)
      @nonLabeledDocuments.each do |nonLabeledDocument|
        nonLabeledDocument.is_classified = false
        nonLabeledDocument.save
      end

      puts 'Finished updating non labeled documents'
    rescue StandardError => e
      puts e
    end
  end

  task documents_content_embedding: :environment do
    puts 'find_documents_content_embedding'
    # Write the 3000 times loops:
    (1..3000).each do |i|
      puts "====== Loop: #{i} ======"
      Apartment::Tenant.each do |tenant|
        Apartment::Tenant.switch!(tenant)
        puts "====== tenant: #{tenant} ======"
        @documents = Document.where.not(content: nil).where(is_document: true).where(is_embedded: false).order('created_at': :desc).first(20)
        puts "====== Documents found: #{@documents.length} ======"
        next unless @documents.present?

        @document = @documents.first
        puts "====== document id: #{@document.id} needs embedding ======"
        puts @document.inspect
        puts "#{ENV['DOCAI_ALPHA_URL']}/documents/embedding"
        response = RestClient::Request.execute(
          method: :post,
          url: "#{ENV['DOCAI_ALPHA_URL']}/documents/embedding",
          payload: {
            document: @document,
            schema: tenant
          }.to_json,
          headers: { content_type: :json },
          timeout: 600
        )
        embeddingRes = response.body
        embeddingRes = JSON.parse(embeddingRes)
        puts "====== embeddingRes: #{embeddingRes}"
        if embeddingRes['status'] == true
          puts "====== document #{@document.id} was successfully processed"
          @document.is_embedded = true
          @document.save!
        else
          puts "====== document #{@document.id} was not successfully processed, error: #{embeddingRes}"
        end
      end
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
