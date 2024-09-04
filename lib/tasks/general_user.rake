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
  task :import_general_users_from_csv, [:file_path] => :environment do |_t, args|
    puts 'Importing users from CSV file...'
    file_path = args[:file_path]

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

  # desc 'Import aienglish general users from a CSV file'
  # task :import_aienglish_general_users_from_csv, [:file_path] => :environment do |_t, args|
  #   puts 'Importing aienglish users from CSV file...'
  #   file_path = args[:file_path]

  #   if file_path.nil? || !File.exist?(file_path)
  #     puts 'File not found'
  #     exit
  #   end

  #   users_data = []
  #   energy_insert_data = []
  #   role_insert_data = []
  #   aienglish_features_data = []
  #   roles_data = []
  #   errors = []
  #   inserted_users = []
  #   email = nil

  #   begin
  #     CSV.foreach(file_path, headers: true) do |row|
  #       puts "Importing user: #{row['email']}"

  #       email = row['email']&.strip
  #       password = row['password']&.strip
  #       nickname = row['name']&.strip.to_s
  #       banbie = row['class_name']&.strip.to_s
  #       class_no = row['class_no']&.strip.to_s

  #       inserted_user = GeneralUser.create!(
  #         email: email,
  #         password: password,
  #         password_confirmation: password,
  #         nickname: nickname,
  #         banbie: banbie,
  #         class_no: class_no
  #       )
  #       inserted_users << inserted_user

  #       # 收集角色数据
  #       roles_data << { email:, role: row['role'] } if row['role'].present?

  #       # 收集 AI English features 数据
  #       if row['aienglish_features'].present?
  #         features = begin
  #           JSON.parse(row['aienglish_features'].gsub(/[“”]/, '"'))
  #         rescue JSON::ParserError
  #           []
  #         end
  #         aienglish_features_data << { email:, features: }
  #       end
  #     end

  #     # 插入用户后，处理其他相关数据
  #     inserted_users.each do |user|
  #       user_id = user.id
  #       email = user.email

  #       # 添加能量值
  #       energy_insert_data << {
  #         user_id: user_id,
  #         user_type: 'GeneralUser',
  #         value: 100,
  #         created_at: Time.now,
  #         updated_at: Time.now
  #       }

  #       # 添加角色
  #       role_row = roles_data.find { |r| r[:email].downcase == email.downcase }
  #       if role_row.present?
  #         role = Role.find_by(name: role_row[:role])
  #         if role.present?
  #           role_insert_data << {
  #             general_user_id: user_id,
  #             role_id: role.id
  #           }
  #         else
  #           errors << { email:, error: "Role '#{role_row[:role]}' not found" }
  #         end
  #       end

  #       # 添加 AI English features
  #       feature_row = aienglish_features_data.find { |f| f[:email].downcase == email.downcase }
  #       if feature_row.present?
  #         user.aienglish_feature_list.add(feature_row[:features], parse: true)
  #         user.save
  #       end
  #     end

  #     # 批量插入 Energy 数据
  #     Energy.insert_all(energy_insert_data) if energy_insert_data.any?

  #     # 批量插入 GeneralUsersRole 数据
  #     GeneralUsersRole.insert_all(role_insert_data) if role_insert_data.any?

  #   rescue ActiveRecord::RecordInvalid => e
  #     errors << { email: email || 'N/A', error: e.record.errors.full_messages.join(', ') }
  #     puts "Failed to import #{email || 'N/A'}: #{e.record.errors.full_messages.join(', ')}"
  #   rescue StandardError => e
  #     errors << { email: email || 'N/A', error: e.message }
  #     puts "Failed to import #{email || 'N/A'}: #{e.message}"
  #   end

  #   if errors.empty?
  #     puts 'Users import completed successfully.'
  #   else
  #     puts "Errors encountered: #{errors}"
  #   end
  # end

  desc 'Import aienglish general users from a CSV file'
  task :import_aienglish_general_users_from_csv, [:file_path] => :environment do |_t, args|
    puts 'Importing aienglish users from CSV file...'
    file_path = args[:file_path]

    if file_path.nil? || !File.exist?(file_path)
      puts 'File not found'
      exit
    end

    errors = []
    email = nil

    begin
      CSV.foreach(file_path, headers: true) do |row|
        email = row['email']&.strip&.downcase
        password = row['password']&.strip
        nickname = row['name']&.strip.to_s
        banbie = row['class_name']&.strip.to_s
        class_no = row['class_no']&.strip.to_s
        aienglish_role = row['role']&.strip
        aienglish_features = begin
          JSON.parse(row['aienglish_features']&.gsub(/[“”]/, '"'))
        rescue JSON::ParserError
          []
        end

        user = GeneralUser.create!(
          email:,
          password:,
          password_confirmation: password,
          nickname:,
          banbie:,
          class_no:
        )

        # 更新meta字段中的aienglish_role和aienglish_features_list
        user.aienglish_role = aienglish_role if aienglish_role.present?
        user.aienglish_features_list = aienglish_features if aienglish_features.any?

        puts "Successfully imported #{email}"
      end
    rescue ActiveRecord::RecordInvalid => e
      errors << { email: email || 'N/A', error: e.record.errors.full_messages.join(', ') }
      puts "Failed to import #{email || 'N/A'}: #{e.record.errors.full_messages.join(', ')}"
    rescue StandardError => e
      errors << { email: email || 'N/A', error: e.message }
      puts "Failed to import #{email || 'N/A'}: #{e.message}"
    end

    if errors.empty?
      puts 'Users import completed successfully.'
    else
      puts "Errors encountered: #{errors}"
    end
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
