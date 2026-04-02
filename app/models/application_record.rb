# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.preferred_microsoft_storage_service
    storage_account_name = ENV['AZURE_STORAGE_NAME'].to_s
    missing_azure_config = [
      storage_account_name,
      ENV['AZURE_STORAGE_ACCESS_KEY'],
      ENV['AZURE_STORAGE_CONTAINER']
    ].any?(&:blank?)

    use_local_storage =
      Rails.env.development? && (
        missing_azure_config ||
        storage_account_name.casecmp('localdevstorage').zero?
      )

    use_local_storage ? :local : :microsoft
  end
end
