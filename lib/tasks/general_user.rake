# frozen_string_literal: true

require 'csv'

namespace :general_user do
  desc 'Import general users from a CSV file'
  task import_general_users_from_csv: :environment do
    puts 'Importing users from CSV file...'
    file_path = '/Users/chonwai/Downloads/general_users.csv'

    CSV.foreach(file_path, headers: true) do |row|
      GeneralUser.create!(
        email: row['email'],
        password: row['password'],
        nickname: "#{row['class']} #{row['name']}"
      )
      puts "Imported #{row['email']} successfully."
    rescue StandardError => e
      puts "Failed to import #{row['email']}: #{e.message}"
    end

    puts 'Users import completed.'
  end
end
