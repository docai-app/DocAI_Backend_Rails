# frozen_string_literal: true

namespace :tags_folder do
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
end
