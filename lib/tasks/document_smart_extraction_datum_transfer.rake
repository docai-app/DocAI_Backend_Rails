# frozen_string_literal: true

namespace :document_smart_extraction_datum_transfer do
  # Create a task for find all has label_ids.first's documents
  task add_document_uploaded_at: :environment do
    puts 'add_document_uploaded_at'
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      @document_smart_extraction_datum = DocumentSmartExtractionDatum.where("meta->>'document_uploaded_at' IS NULL")
      length = @document_smart_extraction_datum.length
      puts "====== Total: #{@document_smart_extraction_datum.length} ======"
      @document_smart_extraction_datum.each do |document_smart_extraction_data|
        @document = Document.find(document_smart_extraction_data.document_id)
        document_smart_extraction_data.meta = {
          document_uploaded_at: @document.created_at
        }
        document_smart_extraction_data.save!
        length -= 1
        puts "====== There are #{length} records left ======"
      end
    end
  end
end
