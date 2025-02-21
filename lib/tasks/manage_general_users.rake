namespace :manage_general_users do
  desc 'Find GeneralUsers by email keywords and update their AI English features'
  task update_aienglish_features_by_email_keywords: :environment do
    email_keywords = ENV['EMAIL_KEYWORDS'] # 從環境變數獲取 email 關鍵字
    new_features = ENV['NEW_FEATURES'] # 從環境變數獲取新的 features

    if email_keywords.blank? || new_features.blank?
      puts 'Please provide email keywords using EMAIL_KEYWORDS and new features using NEW_FEATURES environment variables.'
      exit
    end

    keywords = email_keywords.split(',').map(&:strip) # 將關鍵字分割並去除空白
    features_to_add = new_features.split(',').map(&:strip) # 將新的 features 分割並去除空白

    users = GeneralUser.where('email LIKE ?', '%@%').select do |user|
      keywords.any? { |keyword| user.email.include?(keyword) }
    end

    if users.any?
      puts "Found #{users.count} GeneralUsers with email containing the specified keywords:"
      users.each do |user|
        # 獲取當前的 features list
        current_features = user.aienglish_features_list

        # 將新的 features 添加到 features list 中
        updated_features = current_features + features_to_add

        # 更新 aienglish_features_list
        user.aienglish_features_list = updated_features

        # 確保保存更改
        if user.save
          puts " - Email: #{user.email}, AI English Role: #{user.aienglish_role}, Added features: #{features_to_add.join(', ')}"
        else
          puts "Failed to add features to user: #{user.email}. Errors: #{user.errors.full_messages.join(', ')}"
        end
      end
    else
      puts 'No GeneralUsers found with email containing the specified keywords.'
    end
  end
end
