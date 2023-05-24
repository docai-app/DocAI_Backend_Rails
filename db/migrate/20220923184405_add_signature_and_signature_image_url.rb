# frozen_string_literal: true

class AddSignatureAndSignatureImageUrl < ActiveRecord::Migration[7.0]
  def change
    add_column :document_approvals, :signature, :text, null: true, default: nil
    add_column :document_approvals, :signature_image_url, :string, null: true, default: nil
  end
end
