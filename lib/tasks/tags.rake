# frozen_string_literal: true

namespace :tags do
  task create_folder_for_each_tag: :environment do
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      @tags = ActsAsTaggableOn::Tag.for_context(:labels)
      @tags.each do |tag|
        next if tag.folder_id.present?

        puts "====== tag: #{tag.name} ======"
        @folder = Folder.new(name: tag.name, user_id: nil, parent_id: nil)
        @folder.user = nil
        @folder.save!
        puts "@folder: #{@folder.inspect}"
        puts @folder
        tag.update(folder_id: @folder.id, user_id: nil)
      end
    end
  end

  task update_smart_extraction_schemas_count_on_tag: :environment do
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      Tag.all.each do |t|
        Tag.reset_counters(t.id, :smart_extraction_schemas)
        puts "====== Tag: #{t.name}, smart_extraction_schemas_count: #{t.smart_extraction_schemas_count} ======"
      end
    end
    puts '====== Done ======'
  end
end
