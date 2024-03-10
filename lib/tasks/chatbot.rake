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
end
