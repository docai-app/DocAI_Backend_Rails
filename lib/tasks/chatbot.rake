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

  task add_selected_features_and_title: :environment do
    default_titles = {
      'chatting' => '基本問題',
      'intelligent_mission' => '推薦功能',
      'smart_extract_schema' => '數據生成',
      'chatting_plus' => '專業對話'
    }

    new_titles = {
      'reading_comprehension' => '閱讀理解'
      # If you need to add a new items, you can add it here as well.
    }

    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      length = Chatbot.all.length
      puts "====== Total: #{length} chatbots ======"

      Chatbot.all.each do |chatbot|
        puts "====== chatbot: #{chatbot.inspect} ======"

        chatbot.meta['selected_features'] ||= []
        updated = false

        # Add default features if none are set
        %w[chatting intelligent_mission].each do |feature|
          unless chatbot.meta['selected_features'].include?(feature)
            chatbot.meta['selected_features'] << feature
            updated = true
          end
        end

        # Initialize selected_features_titles if it does not exist
        chatbot.meta['selected_features_titles'] ||= {}

        # Update titles for existing selected features
        chatbot.meta['selected_features'].each do |feature|
          unless chatbot.meta['selected_features_titles'].key?(feature)
            chatbot.meta['selected_features_titles'][feature] = default_titles[feature]
            updated = true
          end
        end

        new_titles.each do |key, value|
          # When the new key does not exist, only add it if it doesn't exist already, and keep the existing custom content.
          if chatbot.meta['selected_features_titles'][key].nil?
            chatbot.meta['selected_features_titles'][key] = value
            updated = true
          end
        end

        # Remove any titles for features that are not selected
        chatbot.meta['selected_features_titles'].slice!(*chatbot.meta['selected_features'])

        # Save the chatbot if there were any changes
        chatbot.save if updated

        length -= 1

        puts "====== There are #{length} records left ======"
      end
    end

    puts 'All chatbots have been updated with default selected features and titles.'
  end
end
