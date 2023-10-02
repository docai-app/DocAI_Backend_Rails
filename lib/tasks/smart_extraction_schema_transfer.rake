# frozen_string_literal: true

namespace :smart_extraction_schema_transfer do
  # Create a task for find all has label_ids.first's documents
  task update_has_label: :environment do
    puts 'update_has_label'
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      @smart_extraction_schemas = SmartExtractionSchema.where('label_id IS NOT NULL')
      length = @smart_extraction_schemas.length
      puts "====== Total: #{length} ======"
      @smart_extraction_schemas.each do |smart_extraction_schema|
        smart_extraction_schema.has_label = true
        smart_extraction_schema.save!
        length -= 1
        puts "====== There are #{length} records left ======"
      end
    end
  end
end
