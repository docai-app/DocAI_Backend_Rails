# frozen_string_literal: true

class ChangeIdentityMetadataName2Meta < ActiveRecord::Migration[7.0]
  def change
    rename_column :identities, :metadata, :meta
  end
end
