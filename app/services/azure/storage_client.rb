require "openssl"
require "securerandom"
require "rbconfig"

# Require the azure storage blob rubygem
require "azure/storage/blob"

$stdout.sync = true

module Azure
    module Resources
        class StorageClient
            def initialize(storage_account_name, storage_account_key)
                @storage_account_name = storage_account_name
                @storage_account_key = storage_account_key
            end

            def get_storage_account_name
                @storage_account_name
            end

            def get_storage_account_key
                @storage_account_key
            end
        end
    end
end