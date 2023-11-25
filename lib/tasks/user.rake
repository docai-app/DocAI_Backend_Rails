# frozen_string_literal: true

namespace :user do
  task add_api_key_for_all_users: :environment do
    puts 'add_api_key_for_all_users'
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      @users = User.all
      @users.each do |user|
        next if user.active_api_key.present?

        ApiKey.create!(
          tenant:,
          user_id: user.id
        )

        puts "====== #{user.email}'s API Key created ======"
      end
    end
  end
end
