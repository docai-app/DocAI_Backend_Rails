# frozen_string_literal: true

require 'csv'

namespace :general_user do

  task saint6: :environment do
    require 'csv'

    # file_path = '/docai-rails/files/Saint6_Account_Password_EssayGrading_20240628_f2aa.csv'
    file_path = '/docai-rails/files/Saint6_Account_Password_EssayGrading_20240628_F2A.csv'

    CSV.foreach(file_path, headers: true) do |row|
      user = GeneralUser.new
      user.nickname = row['name']
      user.banbie = row['class']
      user.class_no = row['no']
      user.email = row['email']
      user.password = row['password']
      user.password_confirmation = row['password']
      if user.save
        puts "GeneralUser #{user.nickname} has been created."
      else
        puts "Failed to create general_user #{row['name']}: #{user.errors.full_messages.join(', ')}"
      end
    end
  end

  desc 'Import general users from a CSV file'
  task import_general_users_from_csv: :environment do
    puts 'Importing users from CSV file...'
    file_path = '/Users/chonwai/Downloads/general_users.csv'

    CSV.foreach(file_path, headers: true) do |row|
      @user = GeneralUser.create!(
        email: row['email'],
        password: row['password'],
        nickname: "#{row['class']} #{row['name']}"
      )
      @user.create_energy(value: 100)
      puts "Imported #{row['email']} successfully."
    rescue StandardError => e
      puts "Failed to import #{row['email']}: #{e.message}"
    end

    puts 'Users import completed.'
  end

  # The production env marketplace_item_id "d1d15a50-b6d0-44d5-82d7-243c3f888c23" is AI English Learning Assistant (Reading Comprehension)
  desc 'Purchase a marketplace item for some general users (From a CSV file)'
  task :purchase_a_marketplace_item_for_some_general_users, [:marketplace_item_id] => :environment do |_t, args|
    marketplace_item = MarketplaceItem.find(args[:marketplace_item_id])

    file_path = '/Users/chonwai/Downloads/general_users.csv'

    CSV.foreach(file_path, headers: true) do |row|
      user = GeneralUser.find_by(email: row['email'])

      custom_name = marketplace_item.chatbot_name
      custom_description = marketplace_item.chatbot_description

      if marketplace_item.purchase_by(user, custom_name, custom_description)
        puts "User #{user.email} purchased item #{marketplace_item.id} successfully."
      else
        puts "Purchase failed for user #{user.email}."
      end
    end
  end

  desc 'Purchase a marketplace item for all general users'
  task :purchase_a_marketplace_item_for_all_general_users, [:marketplace_item_id] => :environment do |_t, args|
    marketplace_item = MarketplaceItem.find(args[:marketplace_item_id])

    GeneralUser.find_each do |user|
      custom_name = marketplace_item.chatbot_name
      custom_description = marketplace_item.chatbot_description

      if marketplace_item.purchase_by(user, custom_name, custom_description)
        puts "User #{user.email} purchased item #{marketplace_item.id} successfully."
      else
        puts "Purchase failed for user #{user.email}."
      end
    end
  end
end
