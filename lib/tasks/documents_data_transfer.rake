namespace :documents_data_transfer do
  # Create a task for find all has label_ids.first's documents
  task update_documents_classified_status: :environment do
    puts "find_documents_with_label_ids"
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      labeledCound = 0
      nonLabeledCount = 0
      labeledDocumentIds = []
      nonLabeledDocumentIds = []
      @documents = Document.includes([:taggings]).order('created_at': :desc).all.as_json(include: [:taggings])

      puts "Number of documents have to check: #{@documents.length}"

      for @document in @documents
        if @document["label_list"].first.present?
          labeledCound += 1
          labeledDocumentIds << @document["id"]
          if labeledCound % 100 == 0
            puts "Number of documents with label: #{labeledCound}"
          end
        elsif @document["label_list"].first.blank?
          nonLabeledCount += 1
          nonLabeledDocumentIds << @document["id"]
          if nonLabeledCount % 100 == 0
            puts "Number of documents without label: #{nonLabeledCount}"
          end
        end
      end
      puts "Number of documents with label: #{labeledCound}"
      puts "Number of documents without label: #{nonLabeledCount}"

      @labeledDocuments = Document.find(labeledDocumentIds)
      # puts @labeledDocuments.inspect
      for @labeledDocument in @labeledDocuments
        @labeledDocument.is_classified = true
        @labeledDocument.save
      end

      puts "Finished updating labeled documents"

      @nonLabeledDocuments = Document.find(nonLabeledDocumentIds)
      # puts @nonLabeledDocuments.inspect
      for @nonLabeledDocument in @nonLabeledDocuments
        @nonLabeledDocument.is_classified = false
        @nonLabeledDocument.save
      end

      puts "Finished updating non labeled documents"
    rescue StandardError => e
      puts e
    end
  end
end
