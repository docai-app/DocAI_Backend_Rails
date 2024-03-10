# frozen_string_literal: true

namespace :chatbot do
  task add_assistive_questions: :environment do
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      length = Chatbot.all.length
      puts "====== Total: #{Chatbot.all.length} chatbots ======"
      Chatbot.all.each do |chatbot|
        puts "====== chatbot: #{chatbot.inspect} ======"
        @documents = []
        next if chatbot.source['folder_id'] == [] || chatbot.source['folder_id'].first == ''

        @folders = chatbot.source['folder_id'].map { |folder| Folder.find(folder) }
        puts @folders.inspect
        @folders.each do |folder|
          puts 'Folder document: ', folder.documents
          @documents.concat(folder.documents)
        end
        @metadata = {
          document_id: @documents.map(&:id),
          language: chatbot.meta['language'] || '繁體中文'
        }
        chatbot.update_assistive_questions(tenant, @metadata)
        length -= 1
        puts "====== There are #{length} records left ======"
      end
    end
  end

  task add_selected_features: :environment do
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      length = Chatbot.all.length
      puts "====== Total: #{Chatbot.all.length} chatbots ======"
      Chatbot.all.each do |chatbot|
        puts "====== chatbot: #{chatbot.inspect} ======"

        # Set the default features if none are set
        chatbot.meta['selected_features'] ||= []
        chatbot.meta['selected_features'] << 'chatting' unless chatbot.meta['selected_features'].include?('chatting')
        unless chatbot.meta['selected_features'].include?('intelligent_mission')
          chatbot.meta['selected_features'] << 'intelligent_mission'
        end

        # Save the chatbot if there were any changes
        chatbot.save if chatbot.changed?

        length -= 1
        puts "====== There are #{length} records left ======"
      end
    end
    puts 'All chatbots have been updated with default selected features.'
  end
end
